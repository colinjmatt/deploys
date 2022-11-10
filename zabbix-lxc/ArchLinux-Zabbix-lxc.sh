#!/bin/bash

pacman -S --noconfirm zabbix-frontend-php zabbix-server zabbix-agent nginx

ln -s /usr/share/webapps/zabbix /srv/http/zabbix
cat ./Configs/ngnx.conf >/etc/nginx/nginx.conf

createuser zabbix
createdb zabbix -O zabbix
cat /usr/share/zabbix-server/postgresql/{schema,images,data}.sql | psql -U zabbix -d zabbix

sed -i -e "\
  s/;extension=bcmath/extension=bcmath/g; \
  s/;extension=curl/extension=curl/g; \
  s/;extension=gd/extension=gd/g; \
  s/;extension=gettext/extension=gettext/g; \
  s/;extension=ldap/extension=ldap/g; \
  s/;extension=pgsql/extension=pgsql/g; \
  s/;extension=sockets/extension=sockets/g; \
  s/;extension=zip/extension=zip/g; \
  s/post_max_size\ =.*/post_max_size\ =\ 16M/g; \
  s/max_execution_time \=.*/max_execution_time\ =\ 300/g; \
  s/max_input_time\ =.*/max_input_time\ =\ 300/g; \
  s/;date.timezone\ =.*/date.timezone\ =\ \"UTC\"/g" \
/etc/php7/php.ini

sed -i -e "\
  s/DBName=.*/DBName=zabbix/g; \
  s/DBUser=.*/DBUser=zabbix/g; \
  s/DBPassword=.*/DBPassword=test/g; \
  s/LogType=.*/LogType=system/g" \
/etc/zabbix/zabbix_server.conf

sed -i -e "\
  s/Server=.*/Server=127.0.0.1/g; \
  s/ServerActive=.*/ServerActive=127.0.0.1/g; \
  s/Hostname=.*/Hostname=Zabbix\ server/g" \
/etc/zabbix/zabbix_agent.conf

openssl req -x509 -nodes -days 36500 -newkey rsa:4096 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt
openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096

systemctl enable \
  nginx \
  zabbix-agent \
  zabbix-server-pgsql --now
