#!/bin/bash
# AWS Lightsail Transmission Server Setup on Amazon Linux
# Name of the server
hostname="example-server"
# FQDN of the server
domain="example.com"
# List of user accounts to create
users="user1 user2 user3 user4 user5"
# List of the above users allowed to SSH to the server
sshusers="user1 user3"
# Change if SSH access should be restricted to an IP or IP range
sship="0.0.0.0/0"
# List of users to become sudoers
sudoers="user1 user4"
# RSS feed that flexget will use
rssfeed="http://some-rss-feed"
# Password for transmission rpc
transmissionpass="password"
# Location of completed downloads
downcomplete="/downloads/complete"
#Location of incomplete downloads
downincomplete="/downloads/incomplete"

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

# Use Cloudflare DNS
cat ./Configs/ifcfg-eth0 >>/etc/sysconfig/network-scripts/ifcfg-eth0

# Set hostname
sed -i -e "s/HOSTNAME=.*/HOSTNAME=""$hostname""/g" /etc/sysconfig/network
hostname $hostname

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config
/etc/init.d/sshd reload

# Configure .bashrc
cat ./Configs/root_bashrc >/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/user_bashrc >/home/ec2-user/.bashrc

# Optimise motd
update-motd --disable
cat ./Configs/motd >/etc/motd
sed -i -e "s/\$domain/""$domain""/g" /etc/motd

# Create users & passwords
for name in $users ; do
    useradd -m "$name"
    echo "Password for $name"
    passwd "$name"
done

# Add sudoers with password required
for name in $sudoers ; do
    echo "$name ALL=(ALL) ALL" >/etc/sudoers.d/"$name"
done

# Add firewall rules
touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
iptables -P INPUT DROP
iptables -A INPUT -i eth0 -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -s localhost --dport 8989 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 9091 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -s localhost --dport 9091 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 55369 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp -s "$sship" --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
/etc/init.d/iptables save

# Install & configure transmission-daemon
# yum install transmission-daemon -y
# 2.92 (14714) is broken. 2.94 can be downloaded instead with the following:
yum remove libevent -y # Only seems to have nfs-utils as a dependency and transmission 2.94 depends on libevent2 2.0.10
( cd /tmp || return
wget  http://geekery.altervista.org/geekery/el6/x86_64/libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-common-2.94-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-daemon-2.94-1.el6.geekery.x86_64.rpm

yum install libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
            transmission-common-2.94-1.el6.geekery.x86_64.rpm \
            transmission-daemon-2.94-1.el6.geekery.x86_64.rpm
)
cat ./Configs/settings.json >/var/lib/tansmission-daemon/settings.json
sed -i -e " s/\$downcomplete/""$downcomplete""/g \
            s/\$downincomplete/""$downincomplete""/g \
            s/\$transmissionpass/""$transmissionpass""/g" \
            /var/lib/tansmission-daemon/settings.json

# Install & configure flexget
pip install --upgrade setuptools
pip install flexget transmissionrpc
mkdir -p /etc/flexget
cat ./Configs/config.yml >/var/lib/flexget/config.yml
sed -i -e " s/\$rssfeed/""$rssfeed""/g \
            s/\$transmissionpass/""$transmissionpass""/g" \
            /var/lib/flexget/config.yml

groupadd -r flexget
useradd -M -r -g flexget -d /var/lib/flexget flexget
mkdir -p /var/lib/flexget
chown -R flexget:flexget /var/lib/flexget/
touch /var/log/flexget.log
chown flexget:flexget /var/log/flexget.log
echo "@reboot flexget /usr/local/bin/flexget -c /var/lib/flexget/config.yml -l /var/log/flexget.log daemon start -d" >/etc/cron.d/flexget

# Install & configure nginx
yum install nginx -y
mkdir -p /var/www/nzbdrone/.well-known
mkdir -p /etc/nginx/sites
cp ./Configs/nginx.conf /etc/nginx/nginx.conf
sudo cp ./Configs/pre-certbot.conf /etc/nginx/sites/nzbdrone.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/
chkconfig nginx on
/etc/init.d/nginx start

curl -L https://dl.eff.org/certbot-auto -o /usr/local/bin/certbot-auto
chmod a+x /usr/local/bin/certbot-auto
/usr/local/bin/certbot-auto certonly --agree-tos --register-unsafely-without-email --webroot -w /var/www/nzbdrone -d "$domain" --debug

cp ./Configs/post-certbot.conf /etc/nginx/sites/nzbdrone.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/nzbdrone.conf

# Install & configure sonarr
yum install mono-core mono-devel mono-locale-extras mediainfo libzen libmediainfo -y
yum install gcc-c++ gcc gettext -y

curl -L http://www.sqlite.org/2014/sqlite-autoconf-3080500.tar.gz -o /tmp/sqlite-autoconf-3080500.tar.gz
tar -zxf /tmp/sqlite-autoconf-*.tar.gz -C /tmp/
cd /tmp/sqlite-autoconf*
./configure  --prefix=/opt/sqlite3.8.5 \
            --disable-static \
            CFLAGS=" -Os \
            -frecord-gcc-switches \
            -DSQLITE_ENABLE_COLUMN_METADATA=1"
make
make install
(
cd /tmp || return
curl -L http://download.sonarr.tv/v2/master/mono/NzbDrone.master.tar.gz -o /tmp/NzbDrone.master.tar.gz
tar zxf /tmp/NzbDrone.master.tar.gz -C /opt/
mv /opt/NzbDrone /opt/nzbdrone
)
groupadd -r nzbdrone
useradd -M -r -g nzbdrone -s /sbin/nologin -d /var/lib/nzbdrone nzbdrone
mkdir -p /var/lib/nzbdrone
chown -R nzbdrone:nzbdrone /var/lib/nzbdrone/ /opt/nzbdrone
curl -L https://raw.githubusercontent.com/OnceUponALoop/RandomShell/master/NzbDrone-init/nzbdrone.init.centos -o /etc/init.d/nzbdrone
curl -L https://raw.githubusercontent.com/OnceUponALoop/RandomShell/master/NzbDrone-init/nzbdrone.init-cfg.centos -o /etc/sysconfig/nzbdrone
chmod +x /etc/init.d/nzbdrone
cat ./Configs/sysconfig-nzbdrone >/etc/sysconfig/nzbdrone
chmod 644 /etc/sysconfig/nzbdrone
chkconfig --add nzbdrone
chkconfig nzbdrone on

# Start services
/etc/init.d/network restart
/etc/init.d/nginx restart
/etc/init.d/transmission-daemon start
/etc/init.d/nzbdrone start

printf "Setup complete.\n"
printf "\033[0;31m\x1b[5m**REBOOT THIS INSTANCE FROM THE AWS CONSOLE\!**\x1b[25m\n"
