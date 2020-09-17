#!/bin/bash
# Mail server deployment using Amazon Linux 2

# FQDN of the server
domain="example.com"
# Leave this blank if no subdomains are required
subdomains="sub1 sub2 sub3"
# Choose one of the above subdomains that will handle webmail. leave blank and a default value of "html" will be used
webmailsub="sub1"

# Install packages
nginx=$(amazon-linux-extras list | grep nginx | awk -F ' ' '{print $2}')
amazon-linux-extras install "$nginx" -y

curl http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -o /tmp/epel-release-latest-7.noarch.rpm
yum install /tmp/epel-release-latest-7.noarch.rpm -y
yum install     certbot \
                clamd clamav clamav-milter \
                dnsmasq \
                dovecot dovecot-pigeonhole \
                fail2ban \
                mailx \
                mariadb-server mysql \
                opendkim opendmarc \
                php php-curl php-fpm php-mcrypt php-xml \
                postgrey \
                spamassassin \
                pypolicyd-spf \
                whois \
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

# configure php-fpm
sed -i -e "s/listen\ =.*/listen\ =\ \/var\/run\/php-fpm\/php-fpm.sock/g" /etc/php-fpm.d/www.conf
sed -i -e "s/user\ =.*/user\ =\ nginx/g" /etc/php-fpm.d/www.conf
sed -i -e "s/group\ =.*/group\ =\ nginx/g" /etc/php-fpm.d/www.conf

# Configure clamav
cat ./Configs/clamav-milter.conf >/etc/mail/clamav-milter.conf
cat ./Configs/scan.conf >/etc/clamd.d/scan.conf
mkdir /var/spool/postfix/clamav-milter
usermod -a -G postfix clamilt
chown clamilt:postfix var/spool/postfix/clamav-milter
mkdir /var/log/clamd
chown clamscan:virusgroup clamd
freshclam

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
cat /Configs/postfix-chroot-cp.sh >/usr/local/bin/postfix-chroot-cp.sh
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
echo "OPTIONS="--unix=/var/spool/postfix/postgrey --delay=60"" >/etc/sysconfig/postgrey

# Configure opendkim & opendmarc
cat ./Configs/opendkim.conf >/etc/opendkim.conf
cat ./Configs/opendmarc.conf >/etc/opendmarc.conf
cat ./Configs/TrustedHosts >/etc/opendkim/TrustedHosts
echo "mail._domainkey.$domain $domain:mail:/etc/opendkim/keys/$domain/mail.private" >/etc/opendkim/KeyTable
echo "*@$domain mail._domainkey.$domain" >/etc/opendkim/SigningTable
mkdir -p /etc/opendkim/keys/$domain
opendkim-genkey -D /etc/opendkim/keys/$domain/ -s mail -d $domain # mail.txt will need to be entered into your domain configuration
chown -R opendkim:opendkim /etc/opendkim/keys/
chmod 0650 /etc/opendkim
chmod 0650 /etc/opendkim/TrustedHosts
usermod -aG opendkim opendmarc
mkdir -p /var/spool/postfix/{opendkim,opendmarc}/
chown opendkim:root /var/spool/postfix/opendkim/
chown opendmarc:root /var/spool/postfix/opendmarc/
usermod -aG opendkim,opendmarc postfix

# Configure fail2ban
cat ./Configs/fail2ban.local >/etc/fail2ban/fail2ban.local
cat ./Configs/jail.local >/etc/fail2ban/jail.local

# Configure nginx
cat ./Configs/nginx.conf >/etc/nginx/nginx.conf
mkdir -p /etc/nginx/sites
cat ./Configs/nginx-pre.conf >/etc/nginx/sites/$domain.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/"$domain".conf

if [ -z "$subdomains" ]; then
    :
else
    for sub in $subdomains ; do
        cat ./Configs/nginx-pre.conf >/etc/nginx/sites/"$sub"."$domain".conf
        sed -i -e "s/\$domain/""$sub"".""$domain""/g" /etc/nginx/sites/"$sub"."$domain".conf
        sed -i -e "s/html/""$sub""/g" /etc/nginx/sites/"$sub"."$domain".conf
    done;
fi

# Install certbot certs
sed -i -e "s/nameserver.*/nameserver\ 1.1.1.1/g" /etc/resolv.conf
mkdir -p /var/www/html/.well-known
systemctl enable nginx --now
certbot certonly --register-unsafely-without-email --agree-tos --webroot -w /var/www/html/ -d $domain
cat ./Configs/index.html >/var/www/html/index.html

if [ -z "$subdomains" ]; then
    :
else
    for sub in $subdomains ; do
        mkdir -p /var/www/"$sub"/.well-known
        certbot certonly --register-unsafely-without-email --agree-tos --webroot -w /var/www/"$sub"/ -d "$sub"."$domain"
        cat ./Configs/index.html >/var/www/"$sub"/index.html
    done;
fi

cat ./Configs/certrenew.sh > /etc/cron.daily/certrenew.sh
chmod +x /etc/cron.daily/certrenew.sh

# Complete nginx setup
cat ./Configs/nginx-post.conf >/etc/nginx/sites/$domain.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/"$domain".conf

if [ -z "$subdomains" ]; then
    :
else
    for sub in $subdomains ; do
        cat ./Configs/nginx-post.conf >/etc/nginx/sites/"$sub"."$domain".conf
        sed -i -e "s/\$domain/""$sub"".""$domain""/g \
                  s/html/""$sub""/g" \
                  /etc/nginx/sites/"$sub"."$domain".conf
    done;
fi

# Populate all configs with $domain
sed -i -e "s/\$domain/""$domain""/g"    /etc/motd \
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

# rainloop webmail server
curl https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop-latest.zip
if [ -z "$webmailsub" ]; then
    webmailsub="html"
else
    :
fi
unzip -q /tmp/rainloop-latest.zip -d /var/www/$webmailsub
find /var/www/$webmailsub/. -type d -exec chmod 755 {} \;
find /var/www/$webmailsub/. -type f -exec chmod 644 {} \;
chown -R nginx:nginx /var/www/$webmailsub
sed -i -e "s/index.html/index.php/g" /etc/nginx/sites/"$webmailsub"."$domain".conf
mysql -u root < ./Configs/rainloop.sql

sed -i -e "s/upload_max_filesize\ =.*/upload_max_filesize\ =\ 1024M/g" /etc/php.ini

# Open necessary ports for Firewalld
ports="22 25 80 143 443 465 993"
for port in $ports; do
    firewall-cmd --permanent --zone=public --add-port="$port"/tcp
done

# Enable EVERYTHING
systemctl enable    clamav-milter \
                    clamd@scan \
                    dovecot \
                    dnsmasq \
                    fail2ban \
                    mariadb \
                    opendmarc \
                    opendkim \
                    postfix \
                    postgrey \
                    php-fpm \
                    spamassassin

rm -rf /tmp/*

printf "Setup complete.\n"
printf "\033[0;31m\x1b[5m**REBOOT THIS INSTANCE FROM THE AWS CONSOLE\!**\x1b[25m\n"
