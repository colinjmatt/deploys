#!/bin/bash

#AWS Mail Server Setup

# TODO
#  /etc/ssl/dhparams.pem
#  /etc/opendkim/private/keys

HOSTNAME=example-server
DOMAIN=example.com
SUBDOMAINS="sub1 sub2 sub3"
USERS="user1 user2 user3 user4 user5"

#Install packages
NGINX=$(amazon-linux-extras list | grep nginx | awk -F ' ' '{print $2}')
amazon-linux-extras install "$NGINX" -y

cd /tmp
curl -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install epel-release-latest-7.noarch.rpm -y
yum install     certbot \
                cifs-utils \
                clamav clamsmtp \
                dnsmasq \
                dovecot dovecot-pigeonhole \
                fail2ban \
                mysql \
                opendkim opendmarc \
                php php-curl php-fpm php-mcrypt php-mysql php-xml \
                postgrey \
                spamassassin \
                pypolicyd-spf \
                -y

# Create swap
dd if=/dev/zero of=/mnt/swapfile bs=1M count=2048
chown root:root /mnt/swapfile
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
echo "/mnt/swapfile swap swap defaults 0 0" >> /etc/fstab
swapon -a

# Set hostname
echo "$HOSTNAME" > /etc/hostname
hostname $HOSTNAME

# Set aliases
cat ./Configs/aliases >/etc/aliases
newaliases

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
systemctl reload sshd

# Configure .bashrc
cat ./Configs/root_bashrc >>/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc

# Make skel mail directories & insert sieve script
mkdir -p /etc/skel/Maildir/{cur,new,tmp}
cat ./Configs/dovecot-sieve >/etc/skel/.dovecot-sieve

# Optimise motd
update-motd --disable
cat ./Configs/motd >/etc/motd

# Configure dnsmasq
cat ./Configs/dnsmasq.conf >/etc/dnsmasq.conf
echo "supersede domain-name-servers 127.0.0.1;" >>/etc/dhcp/dhclient.conf
echo "DNS1=127.0.0.1" >>/etc/sysconfig/network-scripts/ifcfg-eth0

# Configure clamsmtp
cat ./Configs/clamsmtpd.conf >/etc/clamsmtpd.conf

# Configure dovecot
cat ./Configs/dovecot.conf >/etc/dovecot/dovecot.conf
cat ./Configs/10-auth.conf >/etc/dovecot/conf.d/10-auth.conf
cat ./Configs/10-mail.conf >/etc/dovecot/conf.d/10-mail.conf
cat ./Configs/10-master.conf >/etc/dovecot/conf.d/10-master.conf
cat ./Configs/10-ssl.conf >/etc/dovecot/conf.d/10-ssl.conf

sed -i -e "s/ssl_ca\ =\ <\/etc\/letsencrypt\/live\/\$DOMAIN\/chain.pem/ssl_ca\ =\ <\/etc\/letsencrypt\/live\/""$DOMAIN""\/chain.pem/g" /etc/dovecot/conf.d/10-ssl.conf
sed -i -e "s/ssl_cert\ =\ <\/etc\/letsencrypt\/live\/\$DOMAIN\/cert.pem/ssl_ca\ =\ <\/etc\/letsencrypt\/live\/""$DOMAIN""\/cert.pem/g" /etc/dovecot/conf.d/10-ssl.conf
sed -i -e "s/ssl_key\ =\ <\/etc\/letsencrypt\/live\/\$DOMAIN\/privkey.pem/ssl_ca\ =\ <\/etc\/letsencrypt\/live\/""$DOMAIN""\/privkey.pem/g" /etc/dovecot/conf.d/10-ssl.conf

cat ./Configs/15-mailboxes.conf >/etc/dovecot/conf.d/15-mailboxes.conf
cat ./Configs/20-lmtp.conf >/etc/dovecot/conf.d/20-lmtp.conf

sed -i -e "s/\ \ postmaster_address\ =\ postmaster@\$DOMAIN/\ \ postmaster_address\ =\ postmaster@""$DOMAIN""/g" /etc/dovecot/conf.d/20-lmtp.conf

cat ./Configs/90-sieve.conf >/etc/dovecot/conf.d/90-sieve.conf

# Configure postfix
cat ./Configs/main.cf >/etc/postfix/main.cf

sed -i -e "s/myhostname\ \ \ \ \ \ \ \ \ \ \ \ \ =\ \$DOMAIN/myhostname\ \ \ \ \ \ \ \ \ \ \ \ \ =\ ""$DOMAIN""/g" /etc/postfix/main.cf
sed -i -e "s/mydomain\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ =\ \$DOMAIN/mydomain\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ =\ ""$DOMAIN""/g" /etc/postfix/main.cf
sed -i -e "s/myorigin\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ =\ \$DOMAIN/myorigin\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ =\ ""$DOMAIN""/g" /etc/postfix/main.cf

sed -i -e "s/smtpd_tls_cert_file\ \ \ \ =\ \/etc\/letsencrypt\/live\/\$DOMAIN\/cert.pem/smtpd_tls_cert_file\ \ \ \ =\ \/etc\/letsencrypt\/live\/""$DOMAIN""\/cert.pem/g" /etc/postfix/main.cf
sed -i -e "s/smtpd_tls_key_file\ \ \ \ \ =\ \/etc\/letsencrypt\/live\/\$DOMAIN\/privkey.pem/smtpd_tls_key_file\ \ \ \ \ =\ \/etc\/letsencrypt\/live\/""$DOMAIN""\/privkey.pem/g" /etc/postfix/main.cf
sed -i -e "s/smtpd_tls_CAfile\ \ \ \ \ \ \ =\ \/etc\/letsencrypt\/live\/\$DOMAIN\/chain.pem/smtpd_tls_CAfile\ \ \ \ \ \ \ =\ \/etc\/letsencrypt\/live\/""$DOMAIN""\/chain.pem/g" /etc/postfix/main.cf

# TODO in /etc/postfix/main.cf
#smtpd_milters = unix:opendkim/opendkim unix:opendmarc/opendmarc
#non_smtpd_milters = unix:opendkim/opendkim unix:opendmarc/opendmarc
#    check_helo_access hash:/etc/postfix/helo_access,
#    check_sender_access hash:/etc/postfix/sender_access,

cat ./Configs/master.cf >/etc/postfix/master.cf
cat ./Configs/policyd-spf.conf >/etc/python-policyd-spf/policyd-spf.conf
cat ./Configs/helo_access >/etc/postfix/helo_access

sed -i -e "s/\$DOMAIN\ \ \ \ REJECT\ \ \ \ UNAUTHORISED\ USE\ OF\ DOMAIN\ NAME/""$DOMAIN""\ \ \ \ REJECT\ \ \ \ UNAUTHORISED\ USE\ OF\ DOMAIN\ NAME/g" /etc/postfix/helo_access
sed -i -e "s/*.\$DOMAIN\ \ \ \ REJECT\ \ \ \ UNAUTHORISED\ USE\ OF\ DOMAIN\ NAME/*.""$DOMAIN""\ \ \ \ REJECT\ \ \ \ UNAUTHORISED\ USE\ OF\ DOMAIN\ NAME/g" /etc/postfix/helo_access

cat ./Configs/header_checks >/etc/postfix/header_checks
touch /etc/postfix/sender_access
postmap /etc/postfix/sender_access
postmap /etc/postfix/helo_access
postmap /etc/postfix/header_checks
alternatives --set mta /usr/sbin/sendmail.postfix
mkdir -p /var/spool/postfix/etc/

LIST="host.conf hosts localtime nsswitch.conf resolv.conf services"
for FILE in $LIST ; do
  cp /etc/"$FILE" /var/spool/postfix/etc/
done

# Configure spamassassin
cat ./Configs/local.cf >/etc/mail/spamassassin/local.cf
groupadd -r spamd
useradd -r -g spamd -s /sbin/nologin -d /var/lib/spamassassin spamd
mkdir -p /var/lib/spamassassin/.spamassassin
chown -R spamd:spamd /var/lib/spamassassin/

# Configure postgrey
echo "OPTIONS="--unix=/var/spool/postfix/postgrey --delay=60"" >/etc/sysconfig/postgrey

# Configure opendkim & opendmarc
cat<<EOT >/etc/opendkim.conf
AutoRestart             yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           yes
SendReports             yes
SoftwareHeader          yes
LogWhy                  yes
OversignHeaders         From

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Selector                mail
KeyFile                 /etc/opendkim/keys/mail.private

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm	rsa-sha256

UserID                  opendkim:mail

Socket                  local:/var/spool/postfix/opendkim/opendkim
EOT

# TODO
# /etc/opendkim/KeyTable
# /etc/opendkim/SigningTable
# /etc/opendkim/TrustedHosts
# /etc/opendkim/keys/

cat<<EOT >/etc/opendmarc.conf
AutoRestart             yes
AutoRestartRate         10/1h
UMask                   007
UserID 	       	       	opendmarc:mail

Syslog                  true
FailureReportsSentBy    dmarc@matthews-co.xyz
FailureReportsBcc       postmaster@matthews-co.xyz
FailureReports          false
RejectFailures          false

SoftwareHeader          true
SPFIgnoreResults        true
SPFSelfValidate         true

AuthservID              matthews-co.xyz
TrustedAuthservIDs      matthews-co.xyz
IgnoreHosts             /etc/opendkim/TrustedHosts

UserID                  opendmarc:opendmarc
PidFile                 /var/run/opendmarc.pid
Socket                  local:/var/spool/postfix/opendmarc/opendmarc
EOT

mkdir /var/spool/postfix/{opendkim,opendmarc}
chown opendkim:mail /var/spool/postfix/opendkim/
chown opendmarc:mail /var/spool/postfix/opendmarc/

# Configure fail2ban
cat ./Configs/fail2ban.conf >/etc/fail2ban/fail2ban.conf
cat ./Configs/jail.local >/etc/fail2ban/jail.local

# Configure nginx
cat ./Configs/nginx.conf >/etc/nginx/nginx.conf
mkdir -p /etc/nginx/sites
cat ./Configs/nginx-pre.conf >/etc/nginx/sites/"$DOMAIN".conf

sed -i -e "s/\ \ \ \ server_name\ \ \ \$DOMAIN;/\ \ \ \ server_name\ \ \ ""$DOMAIN"";/g" /etc/nginx/sites/"$DOMAIN".conf

for SUB in $SUBDOMAINS ; do
  cp ./Configs/nginx-pre.conf >/etc/nginx/sites/"$SUB"."$DOMAIN".conf
  sed -i -e "s/\ \ \ \ server_name\ \ \ \$DOMAIN;/\ \ \ \ server_name\ \ \ ""$SUB"".""$DOMAIN"";/g" /etc/nginx/sites/"$DOMAIN".conf
done

# Install certbot certs
mkdir -p /var/www/html/.well-known
systemctl enable nginx --now
certbot certonly --register-unsafely-without-email --webroot -w /var/www/html/ -d $DOMAIN
cat ./Configs/index.nginx.html >/var/www/html/index.nginx.html

for SUB in $SUBDOMAINS ; do
  mkdir -p /var/www/"$SUB"/.well-known
  certbot certonly --register-unsafely-without-email --webroot -w /var/www/"$SUB"/ -d "$SUB"."$DOMAIN"
  cat ./Configs/index.nginx.html >/var/www/"$SUB"/index.nginx.html
done

# Complete nginx setup
cat<<EOT >/etc/nginx/sites/1-matthews-co.xyz.conf
server {
    listen        80;
    server_name   matthews-co.xyz;

    if (\$scheme != "https") {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name matthews-co.xyz;
    ssl_certificate /etc/letsencrypt/live/matthews-co.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/matthews-co.xyz/privkey.pem;
    access_log /var/log/nginx/html.access.log;
    error_log /var/log/nginx/html.error.log;

    root /var/www/html;
    index index.nginx.html;

    location / {
        try_files \$uri \$uri/ /index.html?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_index index.php;
        fastcgi_split_path_info ^(.+\.php)(.*)\$;
        fastcgi_keep_conn on;
        include /etc/nginx/fastcgi_params;
        fastcgi_pass unix:/var/run/php/php7.0-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOT

cat<<EOT >/etc/nginx/sites/2-mail.matthews-co.xyz.conf
server {
    listen        80;
    server_name   mail.matthews-co.xyz;

    if (\$scheme != "https") {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name mail.matthews-co.xyz;
    ssl_certificate /etc/letsencrypt/live/mail.matthews-co.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mail.matthews-co.xyz/privkey.pem;
    access_log /var/log/nginx/mail.access.log;
    error_log /var/log/nginx/mail.error.log;

    root /var/www/mail;
    index index.php;
    client_max_body_size 1G;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_index index.php;
        fastcgi_split_path_info ^(.+\.php)(.*)\$;
        fastcgi_keep_conn on;
        include /etc/nginx/fastcgi_params;
        fastcgi_pass unix:/var/run/php/php7.0-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }

    location ^~ /data {
      deny all;
    }

}
EOT

cat<<EOT >/etc/nginx/sites/3-irc.matthews-co.xyz.conf
server {
    listen        80;
    server_name   irc.matthews-co.xyz;

    if (\$scheme != "https") {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name irc.matthews-co.xyz;
    ssl_certificate /etc/letsencrypt/live/irc.matthews-co.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/irc.matthews-co.xyz/privkey.pem;
    access_log /var/log/nginx/irc.access.log;
    error_log /var/log/nginx/irc.error.log;

    location /.well-known {
        alias /var/www/irc/.well-known;
    }

    location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_set_header      Host             \$host;
        proxy_set_header      X-Real-IP        \$remote_addr;
        proxy_set_header      X-Forwarded-For  \$proxy_add_x_forwarded_for;
        proxy_set_header      X-Client-Verify  SUCCESS;
        proxy_set_header      X-Client-DN      \$ssl_client_s_dn;
        proxy_set_header      X-SSL-Subject    \$ssl_client_s_dn;
        proxy_set_header      X-SSL-Issuer     \$ssl_client_i_dn;
        proxy_read_timeout    1800;
        proxy_connect_timeout 1800;
    }
}
EOT

# Create users & passwords
for NAME in $USERS ; do
  useradd -m $NAME
  passwd $NAME
done

# Enable and start EVERYTHING
systemctl enable dnsmasq --now
systemctl enable clamsmtpd --now
systemctl enable dovecot --now
systemctl enable spamassassin --now
systemctl enable fail2ban --now
systemctl enable opendmarc --now
systemctl enable opendkim --now
systemctl enable postgrey --now
systemctl enable postfix --now
systemctl enable offsitemount --now
systemctl restart nginx
