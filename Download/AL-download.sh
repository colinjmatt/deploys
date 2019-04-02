#!/bin/bash
# Media download deployment using Amazon Linux

# FQDN of the server
domain="example.com"
# Password for transmission rpc
transmissionpass="password"
# Location of completed downloads
downcomplete="/downloads/complete"
#Location of incomplete downloads
downincomplete="/downloads/incomplete"

# Create service users
users="sonarr radarr jackett"
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

# Get required packages
yum install mono-core mono-devel mono-locale-extras mediainfo libzen libmediainfo -y

# Install & configure sonarr
( cd /tmp || return
wget http://download.sonarr.tv/v2/master/mono/NzbDrone.master.tar.gz
tar zxf /tmp/NzbDrone.master.tar.gz -C /opt/ )
mv /opt/NzbDrone /opt/nzbdrone
chown -R nzbdrone:nzbdrone /opt/nzbdrone
echo "@reboot sonarr mono /opt/nzbdrone/NzbDrone.exe" >/etc/cron.d/sonarr
mkdir -p /var/lib/sonarr/.config/NzbDrone
echo -e "<Config>\n  <UrlBase>/sonarr</UrlBase>\n</Config>" >/var/lib/sonarr/.config/NzbDrone/config.xml

# Install and configure radarr
( cd /tmp || return
wget https://github.com/Radarr/Radarr/releases/download/v0.2.0.1293/Radarr.develop.0.2.0.1293.linux.tar.gz
tar -zxf Radarr.develop.0.2.0.1293.linux.tar.gz -C /opt/ )
mv /opt/Radarr /opt/radarr
chown -R radarr:radarr /opt/radarr
echo "@reboot radarr mono /opt/radarr/Radarr.exe" >/etc/cron.d/radarr
mkdir -p /var/lib/radarr/.config/Radarr
echo -e "<Config>\n  <UrlBase>/radarr</UrlBase>\n</Config>" >/var/lib/radarr/.config/Radarr/config.xml

# Jackett
( cd /tmp || return
wget https://github.com/Jackett/Jackett/releases/download/v0.11.150/Jackett.Binaries.LinuxAMDx64.tar.gz
tar zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/ )
mv /opt/Jackett /opt/jackett
chown -R jackett:jackett /opt/jackett
echo "@reboot jackett /opt/jackett/jackett" >/etc/cron.d/jackett
mkdir -p /var/lib/jackett/.config/Jackett
echo -e "{\n  \"BasePathOverride\": \"/jackett\"\n}" >/var/lib/jackett/.config/Jackett/ServerConfig.json

# Start services
/etc/init.d/network restart
/etc/init.d/nginx restart
/etc/init.d/transmission-daemon start
/etc/init.d/nzbdrone start

printf "Setup complete.\n"
