#!/bin/sh
wget -O /etc/dnsmasq.adblock 'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext'
systemctl restart dnsmasq
