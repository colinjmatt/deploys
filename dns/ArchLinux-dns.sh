#!/bin/bash
# DNS server deployment using Arch Linux
domain="localdomain" # Local domain name
ipaddress="0.0.0.0" # IP address dns requests will be sent to. comma separated if multiple
dns="0.0.0.1 0.0.0.2" # List of nameservers to be used
netprofile="network-profile" # change to the netctl profile currently in use
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
sed -i -e "s/DNS=.*/DNS=('127.0.0.1')/g" /etc/netctl/"$netprofile"

sed -i -e " s/\$domain/""$domain""/g
            s/\$ipaddress/""$ipaddress""/g" \
            /etc/dnsmasq.conf

# Install and configure pixelserv
cat ./Configs/pixelserv.pl >/usr/local/bin/pixelserv.pl
chmod +x /usr/local/bin/pixelserv.pl /usr/local/bin/adblock.sh
cat ./Configs/pixelserv.service >/etc/systemd/system/pixelserv.service

# Enable services
systemctl enable  adblock.timer \
                  dnsmasq \
                  pixelserv --now
