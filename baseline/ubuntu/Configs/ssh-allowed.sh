#!/bin/bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

ip=$(dig +short "$domain")

# Check if /tmp/ipcheck exists and read the value, otherwise set lastip to an empty string
if [ -f /tmp/ipcheck ]; then
  lastip=$(cat /tmp/ipcheck)
else
  lastip=""
fi

echo "$ip" > /tmp/ipcheck

# Remove old rules if the IP has changed
if [ "$ip" != "$lastip" ]; then
  # Extract all rich rules under the drop zone matching the lastip
  firewallrules=$(firewall-cmd --zone=drop --list-all | sed -n '/rich rules:/,$p' | grep "rule family" | grep "$lastip")

  # Check if there are any rules to remove
  if [ -n "$firewallrules" ]; then
    # Loop over each rule that matches the old IP and remove it
    while IFS= read -r rule; do
      firewall-cmd --zone=drop --remove-rich-rule "$rule"
    done <<< "$firewallrules"
  fi
fi

# Function to check if a rich rule exists
rule_exists() {
  firewall-cmd --zone=drop --list-all | grep -q "rule family=\"ipv4\" source address=\"$ip\" port port=\"$1\" protocol=\"tcp\" accept"
}

# Add the new rules if they don't exist
if ! rule_exists "22"; then
  firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"22\"
    accept"
fi

if ! rule_exists "9091"; then
  firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"9091\"
    accept"
fi

if ! rule_exists "10050"; then
  firewall-cmd --zone=drop --add-rich-rule="
    rule family=\"ipv4\"
    source address=\"$ip\"
    port protocol=\"tcp\"
    port=\"10050\"
    accept"
fi