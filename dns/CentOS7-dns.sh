#!/bin/bash
# DNS server deployment using CentOS
domain="localdomain" # Local domain name
ipaddress="0.0.0.0" # IP address dns requests will be sent to. comma separated if multiple
dns="0.0.0.1 0.0.0.2" # List of nameservers to be used

# Install packages
yum install dnsmasq bind-utils -y

# Configure dnsmasq
cat ./Configs/dnsmasq.hosts >/etc/dnsmasq.hosts
cat ./Configs/adblock.sh >/usr/local/bin/adblock.sh
cat ./Configs/adblock.service >/etc/systemd/system/adblock.service
cat ./Configs/adblock.timer >/etc/systemd/system/adblock.timer
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
for ip in $dns; do
  echo "server=$ip" >>/etc/dnsmasq.conf
done
sed -i -e "s/dns-nameservers.*/dns-nameservers\ \ 127.0.0.1/g" /etc/network/interfaces

sed -i -e " s/\$domain/""$domain""/g
            s/\$ipaddress/""$ipaddress""/g" \
            /etc/dnsmasq.conf

firewall-cmd --permanent --zone=drop --add-port=53/tcp
firewall-cmd --permanent --zone=drop --add-port=53/udp
firewall-cmd --reload

# Install and configure pixelserv
wget -O /usr/local/bin/pixelserv.pl http://proxytunnel.sourceforge.net/files/pixelserv.pl.txt
chmod +x /usr/local/bin/pixelserv.pl /usr/local/bin/adblock.sh
cat ./Configs/pixelserv.service >/etc/systemd/system/pixelserv.service

# Enable services
systemctl enable  adblock.timer \
                  dnsmasq \
                  pixelserv --now
