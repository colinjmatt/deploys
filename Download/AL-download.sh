#!/bin/bash
# Transmission deployment using Amazon Linux

# FQDN of the server
domain="example.com"
# List of users to become sudoers
rssfeed="http://some-rss-feed"
# Password for transmission rpc
transmissionpass="password"
# Location of completed downloads
downcomplete="/downloads/complete"
#Location of incomplete downloads
downincomplete="/downloads/incomplete"

# Create service users
users="flexget nzbdrone jackett"
for name in $users ; do
    groupadd -r "$name"
    useradd -m -r -g "$name" -d /var/lib/"$name" "$name"
    chown -R "$name":"$name" /var/lib/"$name"
done

# Use Cloudflare DNS
cat ./Configs/ifcfg-eth0 >>/etc/sysconfig/network-scripts/ifcfg-eth0

# Add firewall rules
touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
iptables -P INPUT DROP
iptables -A INPUT -p tcp -s localhost --match multiport --dports 8989,9091,9117 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp  --match multiport --dports 80,443,8989,9091,9117,55369 -m state --state NEW,ESTABLISHED -j ACCEPT
/etc/init.d/iptables save

# Install & configure transmission-daemon
# Currently included version (2.92 (14714)) is broken. 2.94 can be downloaded instead with the following:
yum remove libevent -y # Only seems to have nfs-utils as a dependency and transmission 2.94 depends on libevent2 2.0.10
( cd /tmp || return
wget  http://geekery.altervista.org/geekery/el6/x86_64/libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-common-2.94-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-daemon-2.94-1.el6.geekery.x86_64.rpm

yum install libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
            transmission-common-2.94-1.el6.geekery.x86_64.rpm \
            transmission-daemon-2.94-1.el6.geekery.x86_64.rpm )

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
touch /var/log/flexget.log
chown flexget:flexget /var/log/flexget.log
echo "@reboot flexget /usr/local/bin/flexget -c /var/lib/flexget/config.yml -l /var/log/flexget.log daemon start -d" >/etc/cron.d/flexget

# Install & configure nginx with certbot certs
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
yum install mono-core mono-devel mono-locale-extras mediainfo libzen libmediainfo gcc-c++ gcc gettext -y
( cd /tmp || return
wget  http://www.sqlite.org/2014/sqlite-autoconf-3080500.tar.gz
tar -zxf sqlite-autoconf-*.tar.gz
cd /tmp/sqlite-autoconf* || return
./configure --prefix=/opt/sqlite3.8.5 \
            --disable-static \
            CFLAGS=" -Os \
            -frecord-gcc-switches \
            -DSQLITE_ENABLE_COLUMN_METADATA=1"
make
make install
cd /tmp || return
wget http://download.sonarr.tv/v2/master/mono/NzbDrone.master.tar.gz
tar zxf /tmp/NzbDrone.master.tar.gz -C /opt/
mv /opt/NzbDrone /opt/nzbdrone )
chown -R nzbdrone:nzbdrone /opt/nzbdrone
curl -L https://raw.githubusercontent.com/OnceUponALoop/RandomShell/master/NzbDrone-init/nzbdrone.init.centos -o /etc/init.d/nzbdrone
curl -L https://raw.githubusercontent.com/OnceUponALoop/RandomShell/master/NzbDrone-init/nzbdrone.init-cfg.centos -o /etc/sysconfig/nzbdrone
chmod +x /etc/init.d/nzbdrone
cat ./Configs/sysconfig-nzbdrone >/etc/sysconfig/nzbdrone
chmod 644 /etc/sysconfig/nzbdrone
chkconfig --add nzbdrone
chkconfig nzbdrone on

# Jackett
(
cd /tmp || return
wget https://github.com/Jackett/Jackett/releases/download/v0.11.150/Jackett.Binaries.LinuxAMDx64.tar.gz
tar zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/
)
mv /opt/Jackett /opt/jackett
groupadd -r jackett
useradd -M -r -g jackett -d /var/lib/jackett jackett
mkdir -p /var/lib/jackett/Jackett
cat ./Configs/ServerConfig.json  >/var/lib/jackett/Jackett/ServerConfig.json
chown -R jackett:jackett /var/lib/jackett /opt/jackett

# Remove no longer needed packacges
yum remove gcc-c++ gcc gettext -y

# Start services
/etc/init.d/network restart
/etc/init.d/nginx restart
/etc/init.d/transmission-daemon start
/etc/init.d/nzbdrone start

printf "Setup complete.\n"
