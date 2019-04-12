#!/bin/bash
# DNS server deployment using Arch Linux
domain="localdomain" # Local domain name
ipaddress="0.0.0.0" # IP address dns requests will be sent to
dns="0.0.0.1 0.0.0.2" # List of nameservers to be used

# Install packages
pacman -S --noconfirm dnsmasq dnsutils

# Configure dnsmasq
cat ./Configs/dnsmasq.hosts >/etc/dnsmasq.hosts
cat ./Configs/adblock.sh >/usr/local/bin/adblock.sh
cat ./Configs/adblock.service >/etc/systemd/system/adblock.service
cat ./Configs/adblock.timer >/etc/systemd/system/adblock.timer
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
for ip in $dns; do
  echo "server=$ip" >>/etc/dnsmasq.conf
done
sed -i -e "s/DNS=.*/DNS=('127.0.0.1')/g" /etc/netctl/ethernet-static # change to the netctl profile currently in use

# Install and configure pixelserv
wget -O /usr/local/bin/pixelserv.pl http://proxytunnel.sourceforge.net/files/pixelserv.pl.txt
chmod +x /usr/local/bin/pixelserv.pl
cat ./Configs/pixelserv.service >/etc/systemd/system/pixelserv.service

# Enable services
systemctl enable  adblock.timer \
                  dnsmasq \
                  pixelserv --now
