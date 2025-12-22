#!/bin/bash
# Zabbix install for Arch Linux based LXC container

pacman -Syu --noconfirm && pacman -S postgresql zabbix-server zabbix-frontend-php zabbix-agent fping nginx php-fpm php-gd php-pgsql sudo --noconfirm

ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
sed -i -e "s/\#en_GB.UTF-8\ UTF-8/en_GB.UTF-8\ UTF-8/g" /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "KEYMAP=uk" > /etc/vconsole.conf
localectl set-keymap uk
timedatectl set-ntp true

hostnamectl set-hostname "zabbix"
echo "zabbix" > /etc/hostname
echo "127.0.0.1 localhost.localdomain localhost zabbix" > /etc/hosts

echo -e "[Match]\nName=eth0\n\n[Address]\nAddress=192.168.1.131\n\n[Network]\nDNS=192.168.1.1\n\n[Route]\nGateway=192.168.1.1" >/etc/systemd/network/eth0.network

sed -i -e "\
  s/\;extension=bcmath/extension=bcmath/g; \
  s/\;extension=gd/extension=gd/g; \
  s/\;extension=gettext/extension=gettext/g; \
  s/\;extension=ldap/extension=ldap/g; \
  s/\;extension=mysqli/extension=pgsql/g; \
  s/\;extension=sockets/extension=sockets/g; \
  s/post_max_size\ =\ .*/post_max_size\ =\ 16M/g; \
  s/max_execution_time\ =\ .*/max_execution_time\ =\ 300/g; \
  s/max_input_time\ =\ .*/max_input_time\ =\ 300/g; \
  s/;date.timezone\ =/date.timezone\ =\ \"Europe\/London\"/g" \
/etc/php/php.ini

su postgres -P -c 'initdb --locale=en_GB.UTF-8 -E UTF8 -D /var/lib/postgres/data'
systemctl start postgresql
su postgres -P -c 'psql -U postgres -c "create user zabbix"'
su postgres -P -c 'psql -U postgres -c "create database zabbix --owner zabbix"'
su postgres -P -c 'cat /usr/share/zabbix-server/postgresql/schema.sql | psql -d zabbix'
su postgres -P -c 'cat /usr/share/zabbix-server/postgresql/images.sql | psql -d zabbix'
su postgres -P -c 'cat /usr/share/zabbix-server/postgresql/data.sql | psql -d zabbix'

ln -s /usr/share/webapps/zabbix /srv/http/zabbix

sed -i -e "\
  s/\#\ DBPassword=/DBPassword=Zabb1x/g" \
/etc/zabbix/zabbix_server.conf

echo 'Include=/etc/zabbix/zabbix_agentd.conf.d/*.conf' >>/etc/zabbix/zabbix_agentd.conf
mkdir -p /etc/zabbix/zabbix_agentd.conf.d
echo 'UserParameter=archlinuxupdates,checkupdates | wc -l' >/etc/zabbix/zabbix_agentd.conf.d/archlinuxupdates.conf

openssl req -newkey rsa:4096  -x509  -sha512  -days 3650 -nodes -out /etc/ssl/certs/zabbix-self-signed.pem -keyout /etc/ssl/private/zabbix-self-signed.key

cat ./Configs/nginx.conf >/etc/nginx/nginx.conf

openssl rand -hex 32 >/etc/zabbix/zabbix_agentd.psk
chown zabbix:zabbix /etc/zabbix/zabbix_agentd.psk
chmod 640 /etc/zabbix/zabbix_agentd.psk

cat <<EOT >>/etc/zabbix/zabbix_agentd.conf
TLSConnect=psk
TLSAccept=psk
TLSPSKFile=/etc/zabbix/zabbix_agentd.psk
TLSPSKIdentity=PSK001
EOT

echo "SystemMaxUse=50M" >>/etc/systemd/journald.conf

systemctl enable \
  postgresql \
  zabbix-server-pgsql \
  zabbix-agent \
  nginx \
  php-fpm \
  --now