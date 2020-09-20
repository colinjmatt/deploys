#!/bin/bash
LIST="host.conf hosts localtime nsswitch.conf resolv.conf services"

if [ -d /var/spool/postfix/etc ]; then
    :
else
    mkdir -p /var/spool/postfix/etc/
fi

for FILE in $LIST ; do
  cat /etc/"$FILE" >/var/spool/postfix/etc/"$FILE"
done
