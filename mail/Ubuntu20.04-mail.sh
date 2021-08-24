#!/bin/bash
# Mail server deployment using Ubuntu 20.04

domain="example.com" # Domain of the server
subdomain="mail" # Subdomain used for mail
dns="1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4" # List of nameservers to be used
rainlooppassword="" # Needs a sensibly secure password for mysql

# Open necessary ports for Firewalld
ports="25 80 143 443 465 993"
for port in $ports; do
    firewall-cmd --permanent --zone=drop --add-port="$port"/tcp
done
firewall-cmd --reload

# Remove apache if it's installed
apt-get remove -y apache
apt-get autoremove -y

# Install packages
apt-get install -y \
  certbot clamav clamav-daemon clamav-milter \
  dnsmasq dovecot-core dovecot-lmtpd dovecot-imapd dovecot-sieve \
  fail2ban \
  mysql-server \
  nginx \
  opendkim opendkim-tools opendmarc \
  php php-curl php-fpm php-json php-mysql php-pdo php-xml postfix postgrey postfix-policyd-spf-python \
  spamassassin \
  whois \
  zip unzip

# Set aliases
cat ./Configs/aliases >/etc/aliases
newaliases

# Generate Diffie Hellman
openssl dhparam -out /etc/ssl/dhparams.pem 4096

# Make skel mail directories & insert sieve script
mkdir -p /etc/skel/Maildir/{cur,new,tmp}
cat ./Configs/dovecot-sieve >/etc/skel/.dovecot-sieve

for dir in $(ls /home/); do
  cp -r /etc/skel/* /home/"$dir"
  chown -R "$dir":"$dir" /home/"$dir"
done

# Configure dnsmasq
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
systemctl disable systemd-resolved --now
rm /etc/resolv.conf
echo "nameserver 127.0.0.1" >/etc/resolv.conf
for ip in $dns; do
  echo "server=$ip" >>/etc/dnsmasq.conf
done

# Configure clamav
sed -i -e "\
  s/MaxFileSize.*/MaxFileSize 1024M/g; \
  s/MilterSocket.*/MilterSocket\ inet:3310@127.0.0.1/g" \
  /etc/clamav/clamav-milter.conf
sed -i -e "s/StreamMaxLength.*/StreamMaxLength\ 1024M/g" /etc/clamav/clamd.conf

# Configure postfix
cat ./Configs/main.cf >/etc/postfix/main.cf
cat ./Configs/master.cf >/etc/postfix/master.cf
cat ./Configs/policyd-spf.conf >/etc/postfix-policyd-spf-python/policyd-spf.conf
cat ./Configs/helo_access >/etc/postfix/helo_access
cat ./Configs/header_checks >/etc/postfix/header_checks
cat ./Configs/sender_access >/etc/postfix/sender_access
mkfifo /var/spool/postfix/public/pickup
postconf compatibility_level=2

# Configure spamassassin
cat ./Configs/local.cf >/etc/mail/spamassassin/local.cf
groupadd -r spamd
useradd -r -g spamd -s /sbin/nologin -d /var/lib/spamassassin spamd
mkdir -p /var/lib/spamassassin/.spamassassin
chown -R spamd:spamd /var/lib/spamassassin/
sed -i -e "s/CRON=.*/CRON=1/g" /etc/default/spamassassin

# Configure dovecot
cat ./Configs/dovecot.conf >/etc/dovecot/dovecot.conf
cat ./Configs/10-auth.conf >/etc/dovecot/conf.d/10-auth.conf
cat ./Configs/10-mail.conf >/etc/dovecot/conf.d/10-mail.conf
cat ./Configs/10-master.conf >/etc/dovecot/conf.d/10-master.conf
cat ./Configs/10-ssl.conf >/etc/dovecot/conf.d/10-ssl.conf
cat ./Configs/15-mailboxes.conf >/etc/dovecot/conf.d/15-mailboxes.conf
cat ./Configs/20-imap.conf >/etc/dovecot/conf.d/20-imap.conf
cat ./Configs/20-lmtp.conf >/etc/dovecot/conf.d/20-lmtp.conf
cat ./Configs/90-sieve.conf >/etc/dovecot/conf.d/90-sieve.conf

# Configure postgrey
echo "POSTGREY_OPTS=\"--inet=127.0.0.1:10023 --delay=60\"" >/etc/default/postgrey
cat ./Configs/postgrey_whitelist_clients.local /etc/postgrey/postgrey_whitelist_clients.local

# Configure opendkim & opendmarc
cat ./Configs/opendkim.conf >/etc/opendkim.conf
cat ./Configs/opendmarc.conf >/etc/opendmarc.conf
mkdir -p /etc/opendkim/
cat ./Configs/TrustedHosts >/etc/opendkim/TrustedHosts
echo "mail._domainkey.$subdomain.$domain $subdomain.$domain:mail:/etc/opendkim/keys/$subdomain.$domain/mail.private" >/etc/opendkim/KeyTable
echo "*@$domain mail._domainkey.$subdomain.$domain" >/etc/opendkim/SigningTable
mkdir -p /etc/opendkim/keys/"$subdomain"."$domain"
opendkim-genkey -D /etc/opendkim/keys/"$subdomain"."$domain"/ -s mail -d "$subdomain"."$domain" # mail.txt will need to be entered into your domain configuration
chown -R opendkim:opendkim /etc/opendkim
chmod 0750 /etc/opendkim/keys
chmod 0750 /etc/opendkim/keys/"$subdomain"."$domain"
chmod 0600 /etc/opendkim/keys/"$subdomain"."$domain"/mail.private
chmod 0640 /etc/opendkim /etc/opendkim/TrustedHosts
usermod -a -G opendkim opendmarc

# Configure fail2ban
cat ./Configs/fail2ban.local >/etc/fail2ban/fail2ban.local
cat ./Configs/jail.local >/etc/fail2ban/jail.local

# Configure nginx
cat ./Configs/nginx.conf >/etc/nginx/nginx.conf
mkdir -p /etc/nginx/sites
cat ./Configs/nginx-pre.conf >/etc/nginx/sites/"$subdomain"."$domain".conf
sed -i -e "\
  s/\$domain/""$subdomain"".""$domain""/g; \
  s/\$subdomain/""$subdomain""/g" \
  /etc/nginx/sites/"$subdomain"."$domain".conf

# Install certbot certs
mkdir -p /var/www/"$subdomain"/.well-known
cat ./Configs/index.html >/var/www/"$subdomain"/index.html
chmod -R 0755 /var/www/"$subdomain"
chown -R www-data:www-data /var/www/"$subdomain"
systemctl start nginx
certbot certonly --register-unsafely-without-email --agree-tos --webroot -w /var/www/"$subdomain"/ -d "$subdomain"."$domain"
cat ./Configs/certrenew.sh >/etc/cron.daily/certrenew.sh
chmod +x /etc/cron.daily/certrenew.sh

# Complete nginx setup
cat ./Configs/nginx-post.conf >/etc/nginx/sites/"$subdomain"."$domain".conf
sed -i -e "\
  s/\$domain/""$subdomain"".""$domain""/g; \
  s/\$subdomain/""$subdomain""/g" \
  /etc/nginx/sites/"$subdomain"."$domain".conf

# Populate all configs with $domain
sed -i -e "s/\$domain/""$subdomain"".""$domain""/g" \
  /etc/dovecot/conf.d/10-ssl.conf \
  /etc/opendkim.conf

sed -i -e "s/\$domain/""$domain""/g" \
  /etc/dovecot/conf.d/20-lmtp.conf \
  /etc/postfix/helo_access \
  /etc/fail2ban/jail.local \
  /etc/postfix/main.cf \
  /etc/opendmarc.conf \
  /etc/opendkim/TrustedHosts

sed -i -e "s/\$subdomain/""$subdomain""/g" \
  /etc/postfix/main.cf \
  /etc/opendmarc.conf

# Map access and checks for postfix
postmap hash:/etc/postfix/sender_access
postmap hash:/etc/postfix/helo_access
postmap hash:/etc/postfix/header_checks

# Rainloop webmail server configuration
curl https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop-latest.zip
unzip -q /tmp/rainloop-latest.zip -d /var/www/$subdomain
find /var/www/$subdomain/. -type d -exec chmod 755 {} \;
find /var/www/$subdomain/. -type f -exec chmod 644 {} \;
chown -R www-data:www-data /var/www/$subdomain
sed -i -e "s/index.html/index.php/g" /etc/nginx/sites/"$subdomain"."$domain".conf

# MySQL configuration
systemctl start mysql
mysql_secure_installation
sed -i -e "s/\$rainlooppassword/""$rainlooppassword""/g" ./Configs/rainloop.sql
mysql -u root < ./Configs/rainloop.sql -p;

# PHP max file upload size 1GB
sed -i -e "s/upload_max_filesize\ =.*/upload_max_filesize\ =\ 1024M/g" 	/etc/php/7.4/fpm/php.ini

# Enable EVERYTHING
systemctl enable    clamav-milter \
                    dovecot \
                    fail2ban \
                    mysql \
                    nginx \
                    opendmarc \
                    opendkim \
                    postfix \
                    postgrey \
                    php7.4-fpm \
                    spamassassin

rm -rf /tmp/*
