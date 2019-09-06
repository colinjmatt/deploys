#!/bin/bash
# Retrieve and sanitise hosts files from multiple sources and sanitises for use in dnsmasq

dns="10.8.0.1" # Change to the IP that should be fetched when a blocked domain is requested

if [[ -d /tmp/adblock ]]; then
  rm -rf /tmp/adblock
fi
mkdir -p /tmp/adblock
( cd /tmp/adblock || return

# Download and remove any CRLF line breaks from all lists
wget -q -O- http://adaway.org/hosts.txt | tr -d "\r" >adaw-block.txt
sed -i -e 1,24d adaw-block.txt

wget -q -O- http://someonewhocares.org/hosts/zero/hosts | tr -d "\r" >danp-block.txt
sed -i -e 1,85d danp-block.txt

wget -q -O- http://adblock.mahakala.is/hosts | tr -d "\r" >mhka-block.txt

wget -q -O- http://hosts-file.net/ad_servers.txt | tr -d "\r" >mphs-block.txt
sed -i -e 1,10d mphs-block.txt

wget -q -O- http://winhelp2002.mvps.org/hosts.txt | tr -d "\r" >mvps-block.txt
sed -i -e 1,30d mvps-block.txt

wget -q -O- http://www.malwaredomainlist.com/hostslist/hosts.txt | tr -d "\r" >mwdl-block.txt
sed -i -e 1,5d mwdl-block.txt

wget -q -O- https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt | tr -d "\r" >noco-block.txt
sed -i -e 1,11d noco-block.txt

wget -q -O- 'http://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext' | tr -d "\r" >pgly-block.txt
sed -i -e 1,14d pgly-block.txt

# Remove hosts file IP entries
sed -i -e " s/^0.0.0.0//
            s/^127.0.0.1//" \
            adaw-block.txt \
            danp-block.txt \
            mhka-block.txt \
            mphs-block.txt \
            mvps-block.txt \
            mwdl-block.txt \
            noco-block.txt \
            pgly-block.txt

# ALL FILES SANITATION
# Use sed to perform the folloing (in order):
#  - remove any whitespace at the start of any lines
#  - remove any text after and including #
#  - delete all blank lines
#  - add dnsmasq prefix
#  - add dnsmasq suffix
#  - sort, remove duplicates and merge all files in dnsmasq.adblock
sed -i -e "s/^[ \t]*//" *
sed -i -e "s/\#.*$//" *
sed -i -e "/^\s*$/d" *
sed -i -e "s/^/address=\//" *
sed -i -e "s/$/\/""$dns""/" *
cat * | sort | sort -u >dnsmasq.adblock

mv dnsmasq.adblock /etc/ )

# Remove temp dir and restart dnsmasq
rm -rf /tmp/adblock
systemctl restart dnsmasq
