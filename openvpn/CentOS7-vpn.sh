#!/bin/bash
# OpenVPN server deployment with optional ad blocking functionality using CentOS 7

domain="example.com" # FQDN of the server
dns="1.1.1.1 1.0.0.1" # List of nameservers to be used
adblock="yes" # Change to anything but "yes" if ad blocking is not preferred

# Disable as much logging as possible
systemctl disable rsyslog systemd-journald systemd-journald.socket --now

cat ./Configs/rsyslog-systemd.conf >/etc/rsyslog-systemd.conf
rm -rf /etc/rsyslog.d/*

find /var/log/ -type f -name "*" -exec truncate -s 0 {} +

while IFS= read -r -d '' log
do
  ln -sfn /dev/null "$log"
done< <(find /var/log/ -type f -name "*" -print0)

echo "chmod 0666 /dev/null" >>/etc/rc.d/rc.local

# Install packages
yum install wget -y
( cd /tmp || return
wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm )
yum install /tmp/epel-release-latest-7.noarch.rpm -y
yum install openvpn easy-rsa mailx dnsmasq -y

# Disable bash history saving
sed -i -e "s/HISTFILESIZE=.*/HISTFILESIZE=0/g" /root/.bashrc /etc/skel/.bashrc
for dir in /home/*
do
  [[ -d "$dir" ]] || break
  sed -i -e "s/HISTFILESIZE=.*/HISTFILESIZE=0/g" "$dir"/.bashrc
done

# Configure dnsmasq
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
for ip in $dns; do
  echo "server=$ip" >>/etc/dnsmasq.conf
done
sed -i -e "s/dns-nameservers.*/dns-nameservers\ \ 127.0.0.1/g" /etc/network/interfaces

# Configure easy-rsa
mkdir -p /etc/easy-rsa
cp -r /usr/share/easy-rsa/3.0.*/* /etc/easy-rsa

# Generate Diffie Hellman & HMAC
mkdir -p /etc/openvpn/server
openssl dhparam -out /etc/openvpn/server/dh.pem 2048
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Initialise PKI
cat ./Configs/vars >/etc/easy-rsa/vars
( cd /etc/easy-rsa || return
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
echo "net.ipv4.ip_forward = 1" >/etc/sysctl.conf
cat ./Configs/iptables-config >/etc/sysconfig/iptables-config
modprobe iptable_nat
echo 1 | tee /proc/sys/net/ipv4/ip_forward

# For dnsmasq
firewall-cmd --permanent --zone=trusted --add-interface=tun0
firewall-cmd --permanent --zone=trusted --add-interface=tun1

# For openvpn
firewall-cmd --permanent --zone=drop --add-port=443/tcp
firewall-cmd --permanent --zone=drop --add-port=1194/udp
firewall-cmd --permanent --zone=drop --add-service openvpn
firewall-cmd --permanent --zone=drop --add-masquerade
interface=$(ip route get 1.1.1.1 | awk 'NR==1 {print $(NF-2)}')
firewall-cmd --permanent --zone=drop --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$interface" -j MASQUERADE
firewall-cmd --permanent --zone=drop --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.1.0/24 -o "$interface" -j MASQUERADE
firewall-cmd --reload

# Openvpn conifguration
cat ./Configs/server.conf >/etc/openvpn/tcpserver.conf
cat ./Configs/server.conf >/etc/openvpn/udpserver.conf
sed -i -e " s/port\ .*/port\ 1194/g
            s/proto\ .*/proto\ udp4/g
            s/dev\ .*/dev\ tun1/g
            s/10.8.0/10.8.1/g " \
            /etc/openvpn/udpserver.conf

# Client .ovpn profile
mkdir -p /etc/openvpn/template-profiles
mkdir -p /etc/openvpn/client-profiles
cat ./Configs/profile.ovpn >/etc/openvpn/template-profiles/profile.ovpn
sed -i -e "s/\$domain/""$domain""/g" /etc/openvpn/template-profiles/profile.ovp

# Copy cert & ovpn profile generator script
cat ./Configs/gen-ovpn >/usr/local/bin/gen-ovpn
chmod +x /usr/local/bin/gen-ovpn

# ADBLOCK SECTION
if [[ $adblock == "yes" ]]; then
  # Install and configure pixelserv
  wget -O /usr/local/bin/pixelserv.pl http://proxytunnel.sourceforge.net/files/pixelserv.pl.txt
  cat ./Configs/pixelserv.service >/etc/systemd/system/pixelserv.service

  # Setup blocklist update script
  cat ./Configs/adblock.sh >/usr/local/bin/adblock.sh
  cat ./Configs/adblock.service >/etc/systemd/system/adblock.service
  cat ./Configs/adblock.timer >/etc/systemd/system/adblock.timer
  chmod +x /usr/local/bin/pixelserv.pl /usr/local/bin/adblock.sh
  wget -O /etc/dnsmasq.adblock 'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext'
  systemctl enable adblock.timer --now
  echo "conf-file=/etc/dnsmasq.adblock" >> /etc/dnsmasq/dnsmasq.conf
fi
# END ABLOCK SECTION

# Enable and start everything
systemctl restart network
systemctl enable  openvpn@tcpserver \
                  openvpn@udpserver \
                  dnsmasq \
                  pixelserv --now

# Just in case dnsmasq starts up too soon and can't listen on the VPN addresses
systemctl restart dnsmasq

# OPTIONAL - Run:
# systemctl edit --full dnsmasq
#
# Add the following lines to [Service]:
# Restart=on-failure
# RestartSec=5s

# TODO
# Create script for on-demand revocation
# cd /etc/easy-rsa
# ./easyrsa revoke $VPNCLIENT
# ./easyrsa gen-crl
# cp /etc/easy-rsa/pki /etc/openvpn/server/
# sed -i -e "s/.*crl-verify.*/crl-verify\ \/etc\/openvpn\/server\/crl.pem/g"/etc/openvpn/server/server.conf

printf "Setup complete.\n"
