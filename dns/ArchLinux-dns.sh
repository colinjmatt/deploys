#!/bin/bash
# DNS & nfs server deployment using Arch Linux
pacman -S --noconfirm dnsmasq
# /etc/dnsmasq.conf config here
mkdir -p /etc/dnsmasq.d
# blacklist.conf for ad blocking from pgl.yoyo.org
# pixelserv running on 127.0.0.1 port 80
# local.conf for local addresses

#nfs server config here
