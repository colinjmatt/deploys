#!/bin/bash
domain="example.com"
ip=$(dig +short "$domain")

# Check ssh-allowed exists in ipset and create if not
if ! ipset list ssh-allowed > /dev/null 2>&1; then
   ipset create ssh-allowed hash:ip
fi

# Check shh-allowed exists in iptables and create if not
if ! iptables -L -vn | grep "match-set ssh-allowed"  > /dev/null 2>&1; then
   iptables -A IN_drop_allow -p tcp --dport 22 -m set --match-set ssh-allowed src -j ACCEPT
fi

# Check if IP in ssh-allowed matches the current IP of the target domain and update ssh-allowed if not
if [[ "$(ipset list ssh-allowed | tail -n 1)" != "$ip" ]]; then
  ipset flush ssh-allowed
  ipset add ssh-allowed "$ip"
fi
