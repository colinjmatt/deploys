#!/bin/bash
# AWS Lightsail OpenVPN Server Setup on Amazon Linux
HOSTNAME="example-server"
DOMAIN="example.com"
USERS="user1 user2 user3 user4 user5"
SSHUSERS="user1 user3" # List of the above users allowed to SSH to the server
SUDOERS="user1 user4" # List of users to become sudoers

# Install packages
cd /tmp || exit
curl -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install epel-release-latest-7.noarch.rpm

yum install openvpn easy-rsa -y

# Create swap
dd if=/dev/zero of=/mnt/swapfile bs=1M count=2048
chown root:root /mnt/swapfile
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
echo "/mnt/swapfile swap swap defaults 0 0" >> /etc/fstab
swapon -a

# Make /tmp temp filesystem
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Use Cloudflare DNS
cat ./Configs/ifcfg-eth0 >>/etc/sysconfig/network-scripts/ifcfg-eth0

# Set hostname
sed -i -e "s/HOSTNAME=.*/HOSTNAME=""$HOSTNAME""/g" /etc/sysconfig/network
hostname $HOSTNAME

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$SSHUSERS/""$SSHUSERS""/g"
/etc/init.d/sshd reload

# Configure .bashrc
cat ./Configs/root_bashrc >>/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/user_bashrc >/home/ec2-user/.bashrc

# Optimise motd
update-motd --disable
cat ./Configs/motd >/etc/motd

# Create users & passwords
for NAME in $USERS ; do
    useradd -m "$NAME"
    echo "Password for $NAME"
    passwd "$NAME"
done

# Add sudoers with password required
for NAME in $SUDOERS ; do
    echo "$NAME ALL=(ALL) ALL" >/etc/sudoers.d/"$NAME"
done

# Configure easy-rsa
mkdir -p /etc/easy-rsa
cp –r /usr/share/easy-rsa/3.0.3/* /etc/easy-rsa
cat ./Configs/vars >/etc/easy-rsa/vars

# Generate Diffie Hellman & HMAC
mkdir -p /etc/openvpn/server
openssl dhparam -out /etc/openvpn/server/dh.pem 2048
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Initialise PKI
cd /etc/easy-rsa
source ./vars
./easyrsa init-pki

# Generate ca
./easyrsa build-ca nopass
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/server

# Generate & sign server cert
./easyrsa gen-req vpn-server nopass
./easyrsa sign-req server vpn-server
cp /etc/easy-rsa/pki/private/vpn-server.key /etc/openvpn/server/
cp /etc/easy-rsa/pki/issued/vpn-server.crt /etc/openvpn/server/

# Enable ip forwarding
sed -i -e "s/net.ipv4.ip_forward.*/net.ipv4.ip_forward\ =\ 1/g" /etc/sysctl.conf
cat ./Configs/iptables-config >/etc/sysconfig/iptables-config

touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
modprobe iptable_nat
echo 1 | tee /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -s 10.8.0.0/24 -j MASQUERADE
/etc/init.d/iptables save

# Openvpn conifguration
cat ./Configs/server.conf >/etc/openvpn/server.conf

# Client .ovpn profile
mkdir -p /etc/openvpn/template
cat ./Configs/profile.ovpn >/etc/openvpn/template/profile.ovpn
sed -i -e "s/\$DOMAIN/""$DOMAIN""/g"

# TODO
# Create script to generate client certs and ovpn profile on-demand
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1
# Script to take client certs and add to ovpn template and email to requestor
# Take /etc/openvpn/template/profile.ovpn and add the below info:
    #<ca>
    #ca.crt
    #</ca>

    #<cert>
    #client.crt
    #</cert>

    #<key>
    #client.key
    #</key>

    #<tls-auth>
    #ta.key
    #</tls-auth>

# TODO
# Create script for on-demand revocation
# cd /etc/easy-rsa
# ./easyrsa revoke client1
# ./easyrsa gen-crl
# cp /etc/easy-rsa/pki /etc/openvpn/server/
# sed -i -e "s/.*crl-verify.*/crl-verify\ \/etc\/openvpn\/server\/crl.pem/g"/etc/openvpn/server/server.conf
