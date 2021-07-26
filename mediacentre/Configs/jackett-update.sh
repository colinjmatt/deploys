#!/bin/bash
# Destination email and FROM address for emailing any errors
email="$emailsed"
from="$fromsed"

x=""

systemctl disable jackett --now
sleep 5

mv /opt/jackett /opt/jackettold

while [[ ! -d /opt/Jackett && $x -lt 5 ]]; do
  ( cd /tmp || exit 1
  curl -s https://api.github.com/repos/Jackett/Jackett/releases | \
  grep "browser_download_url.*Jackett.Binaries.LinuxAMDx64.tar.gz" | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i- )
  tar -zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/
  x=$(( x + 1 ))
done

if [[ -d /opt/Jackett ]]; then
  mv /opt/Jackett /opt/jackett
  chown -R jackett:jackett /opt/jackett
fi

if [[ -d /opt/jackett ]]; then
  rm -rf /opt/jackettold
  rm /tmp/Jackett.Binaries.LinuxAMDx64.tar.gz
  systemctl enable jackett --now
else
  echo "Jeckett update failed, reverting to previous version." | \
  mail -s "Jackett update failed" \
       -r "$from" \
       "$email"
  mv /opt/jackettold /opt/jackett
  exit 1
fi
