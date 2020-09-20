#!/bin/bash
# Mail server deployment using Centos 8

domain="example.com" # Domain of the server
subdomain="mail" # Subdomain used for mail

# Configure selinux
sed -e "s/SELINUX=.*/SELINUX=enabled/g" /etc/selinux/config
setenforce 1
setsebool -P httpd_can_network_connect 1

# Open necessary ports for Firewalld
ports="25 80 143 443 465 993"
for port in $ports; do
    firewall-cmd --permanent --zone=drop --add-port="$port"/tcp
done
firewall-cmd --reload
systemctl restart firewalld

# Enable epel & Install packages
yum install epel-release -y
yum install     certbot \
                clamd clamav clamav-milter \
                dnsmasq \
                dovecot dovecot-pigeonhole \
                fail2ban \
                mailx \
                mysql mysql-server \
                nginx \
                opendkim opendmarc \
                php php-json php-pdo php-xml \
                postgrey \
                spamassassin \
                pypolicyd-spf \
                whois \
                zip unzip \
                -y

# Generate Diffie Hellman
openssl dhparam -out /etc/ssl/dhparams.pem 4096

# Set aliases
cat ./Configs/aliases >/etc/aliases
newaliases

# Make skel mail directories & insert sieve script
mkdir -p /etc/skel/Maildir/{cur,new,tmp}
cat ./Configs/dovecot-sieve >/etc/skel/.dovecot-sieve

# Configure dnsmasq
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
echo "supersede domain-name-servers 127.0.0.1;" >>/etc/dhcp/dhclient.conf
echo "DNS1=127.0.0.1" >>/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i -e "s/nameserver.*/nameserver\ 127.0.0.1/g" /etc/resolv.conf
cat ./Configs/dns.conf >/etc/NetworkManager/conf.d/dns.conf
systemctl start dnsmasq
systemctl restart NetworkManager

# configure php-fpm
sed -i -e "\
  s/listen\ =.*/listen\ =\ \/var\/run\/php-fpm\/php-fpm.sock/g; \
  s/user\ =.*/user\ =\ nginx/g; \
  s/group\ =.*/group\ =\ nginx/g" \
  /etc/php-fpm.d/www.conf

# Configure clamav
cat ./Configs/clamav-milter.conf >/etc/mail/clamav-milter.conf
cat ./Configs/scan.conf >/etc/clamd.d/scan.conf
mkdir /var/spool/postfix/clamav-milter
usermod -a -G postfix clamilt
chown clamilt:postfix /var/spool/postfix/clamav-milter
mkdir /var/log/clamd
chown clamscan:virusgroup /var/log/clamd
freshclam
chmod 0644 /var/lib/clamav/daily.cld

# Configure dovecot
cat ./Configs/dovecot.conf >/etc/dovecot/dovecot.conf
cat ./Configs/10-auth.conf >/etc/dovecot/conf.d/10-auth.conf
cat ./Configs/10-mail.conf >/etc/dovecot/conf.d/10-mail.conf
cat ./Configs/10-master.conf >/etc/dovecot/conf.d/10-master.conf
cat ./Configs/10-ssl.conf >/etc/dovecot/conf.d/10-ssl.conf
cat ./Configs/15-mailboxes.conf >/etc/dovecot/conf.d/15-mailboxes.conf
cat ./Configs/20-lmtp.conf >/etc/dovecot/conf.d/20-lmtp.conf
cat ./Configs/20-imap.conf >/etc/dovecot/conf.d/20-imap.conf
cat ./Configs/90-sieve.conf >/etc/dovecot/conf.d/90-sieve.conf

# Configure postfix
cat ./Configs/postfix.service >/etc/systemd/system/postfix.service
cat ./Configs/postfix-chroot-cp.sh >/usr/local/bin/postfix-chroot-cp.sh
chmod +x /usr/local/bin/postfix-chroot-cp.sh
cat ./Configs/main.cf >/etc/postfix/main.cf
cat ./Configs/master.cf >/etc/postfix/master.cf
cat ./Configs/policyd-spf.conf >/etc/python-policyd-spf/policyd-spf.conf
cat ./Configs/helo_access >/etc/postfix/helo_access
cat ./Configs/header_checks >/etc/postfix/header_checks
touch /etc/postfix/sender_access
alternatives --set mta /usr/sbin/sendmail.postfix

# Configure spamassassin
cat ./Configs/local.cf >/etc/mail/spamassassin/local.cf
groupadd -r spamd
useradd -r -g spamd -s /sbin/nologin -d /var/lib/spamassassin spamd
mkdir -p /var/lib/spamassassin/.spamassassin
chown -R spamd:spamd /var/lib/spamassassin/

# Configure postgrey
echo "POSTGREY_OPTS=\"--unix=/var/spool/postfix/postgrey/postgrey --pidfile=/var/run/postgrey.pid --delay=60\"" >/etc/sysconfig/postgrey

# Configure opendkim & opendmarc
cat ./Configs/opendkim.conf >/etc/opendkim.conf
cat ./Configs/opendmarc.conf >/etc/opendmarc.conf
cat ./Configs/TrustedHosts >/etc/opendkim/TrustedHosts
echo "mail._domainkey.$subdomain.$domain $subdomain.$domain:mail:/etc/opendkim/keys/$subdomain.$domain/mail.private" >/etc/opendkim/KeyTable
echo "*@$domain mail._domainkey.$subdomain.$domain" >/etc/opendkim/SigningTable
mkdir -p /etc/opendkim/keys/"$subdomain"."$domain"
opendkim-genkey -D /etc/opendkim/keys/"$subdomain"."$domain"/ -s mail -d "$subdomain"."$domain" # mail.txt will need to be entered into your domain configuration
chown -R opendkim:opendkim /etc/opendkim/keys/
chmod 0650 /etc/opendkim
chmod 0650 /etc/opendkim/TrustedHosts
usermod -aG opendkim opendmarc
mkdir -p /var/spool/postfix/{opendkim,opendmarc}/
chown opendkim:root /var/spool/postfix/opendkim/
chown opendmarc:root /var/spool/postfix/opendmarc/
chmod 0755 opendkim opendmarc clamav-milter
usermod -aG opendkim,opendmarc,clamilt postfix

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
chmod -R 0755 /var/www/"$subdomain"
chown -R nginx:nginx /var/www/"$subdomain"
cat ./Configs/index.html >/var/www/"$subdomain"/index.html
systemctl enable nginx --now
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
  /etc/motd \
  /etc/dovecot/conf.d/10-ssl.conf \
  /etc/dovecot/conf.d/20-lmtp.conf \
  /etc/postfix/main.cf \
  /etc/postfix/helo_access \
  /etc/opendkim/TrustedHosts \
  /etc/opendmarc.conf \
  /etc/fail2ban/jail.local

# Map access and checks for postfix
postmap /etc/postfix/sender_access
postmap /etc/postfix/helo_access
postmap /etc/postfix/header_checks

# Rainloop webmail server configuration
curl https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop-latest.zip
unzip -q /tmp/rainloop-latest.zip -d /var/www/$subdomain
find /var/www/$subdomain/. -type d -exec chmod 755 {} \;
find /var/www/$subdomain/. -type f -exec chmod 644 {} \;
chown -R nginx:nginx /var/www/$subdomain
sed -i -e "s/index.html/index.php/g" /etc/nginx/sites/"$subdomain"."$domain".conf

# MySQL configuration
systemctl start mysqld
mysql_secure_installation
mysql -u root < ./Configs/rainloop.sql -p;

# PHP max file upload size 1GB
sed -i -e "s/upload_max_filesize\ =.*/upload_max_filesize\ =\ 1024M/g" /etc/php.ini

# Enable EVERYTHING
systemctl enable    clamav-milter \
                    clamd@scan \
                    dovecot \
                    fail2ban \
                    mysqld \
                    opendmarc \
                    opendkim \
                    postfix \
                    postgrey \
                    php-fpm \
                    spamassassin

rm -rf /tmp/*
