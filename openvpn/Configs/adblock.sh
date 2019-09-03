#!/bin/sh
wget -O /etc/dnsmasq.adblock 'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext'
sed -i -e "s/127.0.0.1/10.8.0.1/g" /etc/dnsmasq.adblock
systemctl restart dnsmasq
