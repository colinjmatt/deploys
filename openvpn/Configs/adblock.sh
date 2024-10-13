#!/bin/bash
# Retrieve and sanitise hosts files from multiple sources and sanitises for use in dnsmasq

if [[ -d /tmp/adblock ]]; then
  rm -rf /tmp/adblock
fi
mkdir -p /tmp/adblock
(
  cd /tmp/adblock || return

  # Download and remove any CRLF line breaks from all lists
  wget -q -O- http://adaway.org/hosts.txt | tr -d "\r" >adaw-block.txt # 127.0.0.1
  sed -i -e 1,24d adaw-block.txt

  wget -q -O- http://someonewhocares.org/hosts/zero/hosts | tr -d "\r" >danp-block.txt # 0.0.0.0
  sed -i -e 1,85d danp-block.txt

  wget -q -O- http://winhelp2002.mvps.org/hosts.txt | tr -d "\r" >mvps-block.txt # 0.0.0.0
  sed -i -e 1,30d mvps-block.txt

  wget -q -O- https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt | tr -d "\r" >noco-block.txt # 0.0.0.0
  sed -i -e 1,11d noco-block.txt

  wget -q -O- 'http://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext' | tr -d "\r" >pgly-block.txt # 127.0.0.1
  sed -i -e 1,14d pgly-block.txt

  # ALL FILES SANITATION
  # Perform the following (in order):
  #  - set any IPs that are 0.0.0.0 to 127.0.0.1
  #  - remove any whitespace at the start of any lines
  #  - remove any text after and including #
  #  - delete all blank lines
  #  - removes any currently blocked domains ready for the updated lists
  #  - sort, remove duplicates and merge all files in dnsmasq.adblock
  sed -i -e " s/^0.0.0.0/127.0.0.1/
              s/^[ \t]*//
              s/\#.*$//
              /^\s*$/d" ./*
  sed -i '/# Blocked Domains/,$!b;//!d' /etc/hosts
  cat ./* | sort | sort -u >>/etc/hosts
)

# Remove temp dir and restart dnsmasq
rm -rf /tmp/adblock