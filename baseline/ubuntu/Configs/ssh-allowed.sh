#!/bin/bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
domain="home.matthews.uk.net"
ip=$(dig +short "$domain")
lastip=$(cat /tmp/ipcheck)

echo "$ip">/tmp/ipcheck


if [ "$ip" != "$lastip" ];then
  firewallrule=$(firewall-cmd --zone=drop --list-all | grep -A 1 "rich rules:" | tail -1 | awk '{$1=$1;print}')
  firewall-cmd --zone=drop --remove-rich-rule "$firewallrule"


 firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"22\"
    accept"
fi
