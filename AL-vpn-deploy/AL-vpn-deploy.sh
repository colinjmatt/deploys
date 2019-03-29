#!/bin/bash
# AWS Lightsail OpenVPN Server Setup on Amazon Linux

# FQDN of the server
domain="example.com"
# List of user accounts to create

# Disable as much logging as possible
cat ./Configs/rsyslog.conf >/etc/rsyslog.conf
rm -rf /etc/rsyslog.d/*
ln -sfn /dev/null /var/log/lastlog
ln -sfn /dev/null /var/log/wtmp
ln -sfn /dev/null /var/log/audit/audit.log

# Install packages
yum-config-manager --enable epel
yum install openvpn easy-rsa mailx -y

# Disable bash history saving
sed -i -e "s/HISTFILESIZE=.*/HISTFILESIZE=0/g" /root/.bashrc /etc/skel/.bashrc
for dir in $(ls -d /home/*)
do
    sed -i -e "s/HISTFILESIZE=.*/HISTFILESIZE=0/g" /home/$dir/.bashrc
done

# Use Cloudflare DNS
cat ./Configs/ifcfg-eth0 >>/etc/sysconfig/network-scripts/ifcfg-eth0

# Configure easy-rsa
mkdir -p /etc/easy-rsa
cp -r /usr/share/easy-rsa/3.0.*/* /etc/easy-rsa

# Generate Diffie Hellman & HMAC
mkdir -p /etc/openvpn/server
openssl dhparam -out /etc/openvpn/server/dh.pem 2048
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Initialise PKI
( cd /etc/easy-rsa || return
cat ./Configs/vars >./vars
source ./vars
./easyrsa init-pki

# Generate ca
./easyrsa build-ca nopass
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/server

# Generate & sign server cert
./easyrsa gen-req vpn-server nopass
./easyrsa sign-req server vpn-server
cp /etc/easy-rsa/pki/private/vpn-server.key /etc/openvpn/server/
cp /etc/easy-rsa/pki/issued/vpn-server.crt /etc/openvpn/server/ )

# Enable ip forwarding & firewall hardening rules
sed -i -e "s/net.ipv4.ip_forward.*/net.ipv4.ip_forward\ =\ 1/g" /etc/sysctl.conf
cat ./Configs/iptables-config >/etc/sysconfig/iptables-config

touch /etc/sysconfig/ip6tables
chkconfig ip6tables on
/etc/init.d/ip6tables start
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
/etc/init.d/ip6tables save

touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
modprobe iptable_nat
echo 1 | tee /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -s 10.8.0.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 10.8.1.0/24 -j MASQUERADE
iptables -P INPUT DROP
iptables -A INPUT -i eth0 -p tcp --match multiport --dports 443,1194 -m state --state NEW,ESTABLISHED -j ACCEPT
/etc/init.d/iptables save

# Openvpn conifguration
cat ./Configs/tcpserver.conf >/etc/openvpn/tcpserver.conf
cat ./Configs/udpserver.conf >/etc/openvpn/udpserver.conf

# Client .ovpn profile
mkdir -p /etc/openvpn/template-profiles
mkdir -p /etc/openvpn/client-profiles
cat ./Configs/profile.ovpn >/etc/openvpn/template-profiles/profile.ovpn
sed -i -e "s/\$domain/""$domain""/g" /etc/openvpn/template-profiles/profile.ovpn

# Copy cert & ovpn profile generator script
cat ./Configs/gen-ovpn >/usr/local/bin/gen-ovpn
chmod +x /usr/local/bin/gen-ovpn

# Start and enable openvpn
/etc/init.d/network restart
chkconfig openvpn on
/etc/init.d/openvpn start

# TODO
# Create script for on-demand revocation
# cd /etc/easy-rsa
# ./easyrsa revoke $VPNCLIENT
# ./easyrsa gen-crl
# cp /etc/easy-rsa/pki /etc/openvpn/server/
# sed -i -e "s/.*crl-verify.*/crl-verify\ \/etc\/openvpn\/server\/crl.pem/g"/etc/openvpn/server/server.conf

printf "Setup complete.\n"
