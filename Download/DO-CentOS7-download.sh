#!/bin/bash
# Media downaload deployment using Digital Ocean CentOS 7

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
users="sonarr radarr jackett"
for name in $users ; do
    groupadd -r "$name"
    useradd -m -r -g "$name" -d /var/lib/"$name" "$name"
    chown -R "$name":"$name" /var/lib/"$name"
done

# Use Cloudflare DNS
sed -i -e "s/dns-nameservers.*/dns-nameservers\ \ 1.1.1.1\ 1.0.0.1/g" /etc/network/interfaces

# Add firewall rules
#ports="80 443 7878 8989 9091 9117 55369" # internal ports don't need opening
ports="80 443 9091 55369"
for port in $ports; do
    firewall-cmd --permanent --zone=public --add-port="$port"/tcp
done

# Enable epel
yum install wget -y
( cd /tmp || return
wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install /tmp/epel-release-latest-7.noarch.rpm -y

# Install & configure transmission-daemon
yum install transmission-daemon -y
cat ./Configs/settings.json >/var/lib/tansmission-daemon/settings.json
sed -i -e " s/\$downcomplete/""$downcomplete""/g \
            s/\$downincomplete/""$downincomplete""/g \
            s/\$transmissionpass/""$transmissionpass""/g" \
            /var/lib/tansmission-daemon/settings.json

# Install & configure nginx with certbot certs
yum install nginx certbot -y
mkdir -p /var/www/nzbdrone/.well-known
mkdir -p /etc/nginx/sites
cp ./Configs/nginx.conf /etc/nginx/nginx.conf
sudo cp ./Configs/pre-certbot.conf /etc/nginx/sites/nzbdrone.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/
systemctl enable nginx --now
certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /var/www/nzbdrone -d "$domain" --debug
cp ./Configs/post-certbot.conf /etc/nginx/sites/nzbdrone.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/nzbdrone.conf

# Get required packages
yum install mono-core mono-locale-extras mediainfo libicu libcurl-devel bzip2 -y

# Install & configure sonarr
( cd /tmp || return
wget http://download.sonarr.tv/v2/master/mono/NzbDrone.master.tar.gz
tar zxf /tmp/NzbDrone.master.tar.gz -C /opt/
mv /opt/NzbDrone /opt/nzbdrone )
chown -R sonarr:sonarr /opt/nzbdrone
cat ./Configs/sonarr.service >/etc/systemd/system/sonarr.service
echo -e "<Config>\n  <UrlBase>/sonarr</UrlBase>\n</Config>" >/var/lib/sonarr/.config/NzbDrone/config.xml


# Install and configure radarr
( cd /tmp || return
wget https://github.com/Radarr/Radarr/releases/download/v0.2.0.1293/Radarr.develop.0.2.0.1293.linux.tar.gz
tar -zxf Radarr.develop.0.2.0.1293.linux.tar.gz -C /opt/ )
mv /opt/Radarr /opt/radarr
chown -R radarr:radarr /opt/radarr
echo -e "<Config>\n  <UrlBase>/radarr</UrlBase>\n</Config>" >/var/lib/radarr/.config/Radarr/config.xml

# Install & configure jackett
( cd /tmp || return
wget https://github.com/Jackett/Jackett/releases/download/v0.11.150/Jackett.Binaries.LinuxAMDx64.tar.gz
tar zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/ )
mv /opt/Jackett /opt/jackett
chown -R jackett:jackett /opt/jackett
cat ./Configs/jackett.service >/etc/systemd/system/jackett.service
echo -e "{\n  \"BasePathOverride\": \"/jackett\"\n}" >/var/lib/jackett/.config/Jackett/ServerConfig.json

# Start services
systemctl restart network \
                  nginx
systemctl enable  transmission-daemon \
                  nzbdrone \
                  radarr \
                  jackett --now \

printf "Setup complete.\n"
