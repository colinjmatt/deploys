#!/bin/bash
# AWS Mail Server Setup on Amazon Linux 2

HOSTNAME=example-server
DOMAIN=example.com
SUBDOMAINS="sub1 sub2 sub3" # Leave this blank if no subdomains are required
WEBMAILSUB="sub1" # Choose one of the above subdomains that will handle webmail. leave blank if a subdomain isn't being used for the rainloop frontend
USERS="user1 user2 user3 user4 user5"
SSHUSERS="user1 user3" # List of the above users allowed to SSH to the server
SUDOERS="user1 user4" # List of users to become sudoers

# Install packages
NGINX=$(amazon-linux-extras list | grep nginx | awk -F ' ' '{print $2}')
amazon-linux-extras install "$NGINX" -y

curl http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -o /tmp/epel-release-latest-7.noarch.rpm
yum install /tmp/epel-release-latest-7.noarch.rpm -y
yum install     certbot \
                clamav clamsmtp \
                dnsmasq \
                dovecot dovecot-pigeonhole \
                fail2ban \
                mariadb-server mysql \
                opendkim opendmarc \
                php php-curl php-fpm php-mcrypt php-xml \
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

# Make /tmp temp filesystem
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Generate Diffie Hellman
openssl dhparam -out /etc/ssl/dhparams.pem 4096

# Set hostname
echo "$HOSTNAME" > /etc/hostname
hostname $HOSTNAME

# Set aliases
cat ./Configs/aliases >/etc/aliases
newaliases

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$SSHUSERS/""$SSHUSERS""/g"
systemctl reload sshd

# Configure .bashrc
cat ./Configs/root_bashrc >>/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/user_bashrc >/home/ec2-user/.bashrc

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
sed -i -e "s/nameserver.*/nameserver\ 127.0.0.1/g" /etc/resolv.conf

# configure php-fpm
sed -i -e "s/listen\ =.*/listen\ =\ \/var\/run\/php-fpm\/php-fpm.sock/g" /etc/php-fpm.d/www.conf
sed -i -e "s/user\ =.*/user\ =\ nginx/g" /etc/php-fpm.d/www.conf
sed -i -e "s/group\ =.*/group\ =\ nginx/g" /etc/php-fpm.d/www.conf

# Configure clamsmtp
cat ./Configs/clamsmtpd.conf >/etc/clamsmtpd.conf
freshclam

# Configure dovecot
cat ./Configs/dovecot.conf >/etc/dovecot/dovecot.conf
cat ./Configs/10-auth.conf >/etc/dovecot/conf.d/10-auth.conf
cat ./Configs/10-mail.conf >/etc/dovecot/conf.d/10-mail.conf
cat ./Configs/10-master.conf >/etc/dovecot/conf.d/10-master.conf
cat ./Configs/10-ssl.conf >/etc/dovecot/conf.d/10-ssl.conf
cat ./Configs/15-mailboxes.conf >/etc/dovecot/conf.d/15-mailboxes.conf
cat ./Configs/20-lmtp.conf >/etc/dovecot/conf.d/20-lmtp.conf
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
echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" >/etc/opendkim/KeyTable
echo "*@$DOMAIN mail._domainkey.$DOMAIN" >/etc/opendkim/SigningTable
mkdir -p /etc/opendkim/keys/$DOMAIN
opendkim-genkey -D /etc/opendkim/keys/$DOMAIN/ -s mail -d $DOMAIN # mail.txt will need to be entered into your domain configuration
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
cat ./Configs/nginx-pre.conf >/etc/nginx/sites/$DOMAIN.conf
sed -i -e "s/\$DOMAIN/""$DOMAIN""/g" /etc/nginx/sites/"$DOMAIN".conf

if [ -z "$SUBDOMAINS" ]; then
    :
else
    for SUB in $SUBDOMAINS ; do
        cat ./Configs/nginx-pre.conf >/etc/nginx/sites/"$SUB"."$DOMAIN".conf
        sed -i -e "s/\$DOMAIN/""$SUB"".""$DOMAIN""/g" /etc/nginx/sites/"$SUB"."$DOMAIN".conf
        sed -i -e "s/html/""$SUB""/g" /etc/nginx/sites/"$SUB"."$DOMAIN".conf
    done;
fi

# Install certbot certs
sed -i -e "s/nameserver.*/nameserver\ 208.67.220.220/g" /etc/resolv.conf
mkdir -p /var/www/html/.well-known
systemctl enable nginx --now
certbot certonly --register-unsafely-without-email --webroot -w /var/www/html/ -d $DOMAIN
cat ./Configs/index.html >/var/www/html/index.html

if [ -z "$SUBDOMAINS" ]; then
    :
else
    for SUB in $SUBDOMAINS ; do
        mkdir -p /var/www/"$SUB"/.well-known
        certbot certonly --register-unsafely-without-email --webroot -w /var/www/"$SUB"/ -d "$SUB"."$DOMAIN"
        cat ./Configs/index.html >/var/www/"$SUB"/index.html
    done;
fi

# Complete nginx setup
cat ./Configs/nginx-post.conf >/etc/nginx/sites/$DOMAIN.conf
sed -i -e "s/\$DOMAIN/""$DOMAIN""/g" /etc/nginx/sites/"$DOMAIN".conf

if [ -z "$SUBDOMAINS" ]; then
    :
else
    for SUB in $SUBDOMAINS ; do
        cat ./Configs/nginx-post.conf >/etc/nginx/sites/"$SUB"."$DOMAIN".conf
        sed -i -e "s/\$DOMAIN/""$SUB"".""$DOMAIN""/g" /etc/nginx/sites/"$SUB"."$DOMAIN".conf
        sed -i -e "s/html/""$SUB""/g" /etc/nginx/sites/"$SUB"."$DOMAIN".conf
    done;
fi

# Populate all configs with $DOMAIN
sed -i -e "s/\$DOMAIN/""$DOMAIN""/g"    /etc/motd \
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
if [ -z "$WEBMAILSUB" ]; then
    WEBMAILSUB="html"
else
    :
fi
unzip -q /tmp/rainloop-latest.zip -d /var/www/$WEBMAILSUB
find /var/www/$WEBMAILSUB/. -type d -exec chmod 755 {} \;
find /var/www/$WEBMAILSUB/. -type f -exec chmod 644 {} \;
chown -R nginx:nginx /var/www/$WEBMAILSUB
sed -i -e "s/index.html/index.php/g" /etc/nginx/sites/"$WEBMAILSUB"."$DOMAIN".conf

# Create users & passwords
for NAME in $USERS ; do
    useradd -m "$NAME"
    echo "Password for $NAME"
    passwd "$NAME"
done

# Add sudoers with password required
for NAME in $SUDOERS ; do
    echo "$NAME ALL=(ALL) ALL" >/etc/sudoers.d/"$NAME"
done

# Open necessary ports for Firewalld
PORTS="22 25 80 143 443 465 993"
for PORT in $PORTS; do
    firewall-cmd --permanent --zone=public --add-port="$PORT"/tcp
done

# Enable EVERYTHING
systemctl enable clamsmtpd
systemctl enable clamsmtp-clamd
systemctl enable dovecot
systemctl enable dnsmasq
systemctl enable fail2ban
systemctl enable mariadb
systemctl enable opendmarc
systemctl enable opendkim
systemctl enable postfix
systemctl enable postgrey
systemctl enable php-fpm
systemctl enable spamassassin

rm -rf /tmp/*

printf "Setup complete.\n"
printf "\033[0;31m\x1b[5m**REBOOT THE EC2 INSTANCE FROM THE AWS CONSOLE\!**\x1b[25m\n"

# TODO
# certbot renew cron job
# freshclam cron job
# mysql-server config
