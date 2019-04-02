#!/bin/bash
# Flexget isn't installed as default but will remain here in case it is useful

# List of users to become sudoers
rssfeed="http://some-rss-feed"
# Password for transmission rpc
transmissionpass="password"

groupadd -r flexget
useradd -m -r -g flexget -d /var/lib/flexget flexget
chown -R flexget:flexget /var/lib/flexget

if [[ -d /etc/systemd ]]; then
  # Amazon Linux 2 (systemd)
  pip install --upgrade setuptools
  pip install flexget transmissionrpc
  mkdir -p /etc/flexget
  cat ./Configs/config.yml >/var/lib/flexget/config.yml
  sed -i -e " s/\$rssfeed/""$rssfeed""/g \
              s/\$transmissionpass/""$transmissionpass""/g" \
              /var/lib/flexget/config.yml
  touch /var/log/flexget.log
  chown flexget:flexget /var/log/flexget.log
  cat ./Configs/flexget.service >/etc/systemd/system/flexget.service
  systemctl enable flexget --now
else
  # Amazon Linux (init.d)
  pip install --upgrade setuptools
  pip install flexget transmissionrpc
  mkdir -p /etc/flexget
  cat ./Configs/config.yml >/var/lib/flexget/config.yml
  sed -i -e " s/\$rssfeed/""$rssfeed""/g \
              s/\$transmissionpass/""$transmissionpass""/g" \
              /var/lib/flexget/config.yml
  touch /var/log/flexget.log
  chown flexget:flexget /var/log/flexget.log
  echo "@reboot flexget /usr/local/bin/flexget -c /var/lib/flexget/config.yml -l /var/log/flexget.log daemon start -d" >/etc/cron.d/flexget
fi
