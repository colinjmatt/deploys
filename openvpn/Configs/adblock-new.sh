#!/bin/bash
# Retrieve and sanitise hosts files from multiple sources and sanitises for use in dnsmasq

dns="10.8.0.1" # Change to the IP that should be fetched when a blocked domain is requested

if [[ -d /tmp/adblock ]]; then
  rm -rf /tmp/adblock
fi
mkdir -p /tmp/adblock
( cd /tmp/adblock || return

wget -qO adaw-block.txt http://adaway.org/hosts.txt
sed -i -e 1,24d adaw-block.txt

wget -qO danp-block.txt http://someonewhocares.org/hosts/zero/hosts
sed -i -e 1,85d danp-block.txt

wget -qO mhka-block.txt http://adblock.mahakala.is/hosts

wget -qO mphs-block.txt http://hosts-file.net/ad_servers.txt
sed -i -e 1,24d mphs-block.txt

wget -qO mvps-block.txt http://winhelp2002.mvps.org/hosts.txt
sed -i -e 1,30d mvps-block.txt

wget -qO mwdl-block.txt http://www.malwaredomainlist.com/hostslist/hosts.txt
sed -i -e 1,5d mwdl-block.txt

wget -qO noco-block.txt https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt
sed -i -e 1,11d noco-block.txt

wget -qO pgly-block.txt 'http://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext'
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
# Remove any whitespace at the start of any lines
sed -i -e "s/^[ \t]*//" *
# Remove any text after and including #
sed -i -e "s/\#.*$//" *
# Delete all blank lines
sed -i -e "/^\s*$/d" *
# add dnsmasq prefix
sed -i -e "s/^/address=\//" *
# add dnsmasq suffix
sed -i -e "s/$/\/""$dns""/" *

cat * | sort | sort -u >dnsmasq.adblock

mv dnsmasq.adblock /etc/ )

rm -rf /tmp/adblock
