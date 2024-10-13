#!/bin/bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

ip=$(dig +short "$domain")

# Check if /tmp/ipcheck exists and read the value, otherwise set lastip to an empty string
if [ -f /tmp/ipcheck ]; then
  lastip=$(cat /tmp/ipcheck)
else
  lastip=""
fi

echo "$ip">/tmp/ipcheck

# Only proceed if the IP has changed
if [ "$ip" != "$lastip" ]; then
  # Extract all rich rules under the drop zone
  firewallrules=$(firewall-cmd --zone=drop --list-all | sed -n '/rich rules:/,$p' | grep "rule family" | grep "$lastip")
  
  # Loop over each rule that matches the old IP and remove it
  while IFS= read -r rule; do
    firewall-cmd --zone=drop --remove-rich-rule "$rule"
  done <<< "$firewallrules"

  # Add the new rule with the updated IP
  firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"22\"
    accept"

 firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"9091\"
    accept"

 firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"10050\"
    accept"
fi