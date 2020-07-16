#!/bin/bash
systemctl stop jackett
sleep 5

mv /opt/jackett /opt/jackettold

( cd /tmp || return
curl -s https://api.github.com/repos/Jackett/Jackett/releases | grep "browser_download_url".*Jackett.Binaries.LinuxAMDx64.tar.gz | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i-
tar -zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/ )
mv /opt/Jackett /opt/jackett
chown -R jackett:jackett /opt/jackett

rm -rf /opt/jackettold

systemctl start jackett
