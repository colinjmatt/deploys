#!/bin/bash
x=""

systemctl disable jackett --now
sleep 5

mv /opt/jackett /opt/jackettold

while [[ ! -d /opt/Jackett && $x -lt 5 ]]; do
  ( cd /tmp || exit 1
  curl -X GET https://api.github.com/repos/Jackett/Jackett/releases -H "Accept: application/json" | \
  grep "browser_download_url.*Jackett.Binaries.LinuxAMDx64.tar.gz" | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i-
  tar -zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/)
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
  mv /opt/jackettold /opt/jackett
  systemctl enable jackett --now
  exit 1
fi
