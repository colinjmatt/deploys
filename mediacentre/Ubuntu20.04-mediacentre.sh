#!/bin/bash
# Media server deployment using CentOS 8

# FQDN of the server
domain="example.com"
# Name of non-root user to install Plex as (usually the user you will ssh with)
user="user1"
# Password for transmission rpc (needs to be single-quoted)
transmissionpass='password'
# Address to send errors to
email="user@example.com"
# Identity of sender (email or name)
from="root@example.com"
# Location of completed downloads
downcomplete='/Media/Downloads/Complete'
# Location of incomplete downloads
downincomplete='/Media/Downloads/Incomplete'
# Location of films and TV shows
tv='/Media/TV Shows'
films='/Media/Films'

# Create download directories
mkdir -p "$downcomplete"; chmod -R 0777 "$downcomplete"
mkdir -p "$downincomplete"; chmod -R 0777 "$downincomplete"
mkdir -p "$tv"; chmod -R 0777 "$tv"
mkdir -p "$films"; chmod -R 0777 "$films"

# Ensure permissions for downloads and media are set... permissively
cat ./Configs/permissions.sh >/usr/local/bin/permissions.sh
echo "*/5 * * * * root /usr/local/bin/permissions.sh" >/etc/cron.d/permissions
sed -i -e "\
  s|\$tv|""$tv""|g; \
  s|\$films|""$films""|g; \
  s|\$downcomplete|""$downcomplete""|g" \
/usr/local/bin/permissions.sh

# Create service users
users="sonarr radarr jackett transmission"
for name in $users ; do
    groupadd -r "$name"
    useradd -m -r -g "$name" -d /var/lib/"$name" "$name"
    chown -R "$name":"$name" /var/lib/"$name"
done

# Use Cloudflare DNS
echo "DNS=1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4" >> /etc/systemd/resolved.conf
systemctl restart systemd-resolved

# Add firewall rules
ports="80 443 9091 32400 55369" # port 9091 only if a client is to be used to access transmission
for port in $ports; do
    firewall-cmd --permanent --zone=drop --add-port="$port"/tcp
done
firewall-cmd --reload

# Install & configure nginx with certbot certs
apt-get -y install nginx certbot
mkdir -p /usr/share/nginx/html/.well-known
chmod 0755 /usr/share/nginx/html/.well-known/
mkdir -p /etc/nginx/sites
cat ./Configs/nginx.conf >/etc/nginx/nginx.conf
cat ./Configs/pre-certbot.conf >/etc/nginx/sites/mediacentre.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/mediacentre.conf
useradd -r nginx
systemctl enable nginx --now
certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /usr/share/nginx/html -d "$domain"
cat ./Configs/post-certbot.conf >/etc/nginx/sites/mediacentre.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/mediacentre.conf
cat ./Configs/certbot-auto >/usr/local/bin/certbot-auto
echo "@daily root /usr/local/bin/certbot-auto >/dev/null 2>&1" >/etc/cron.d/certbot

# Generate Diffie Hellman
openssl dhparam -out /etc/ssl/dhparams.pem 4096

# Install & configure transmission-daemon
apt-get -y install transmission-daemon
mkdir -p /var/lib/transmission/.config/transmission-daemon/
cat ./Configs/settings.json >/var/lib/transmission/.config/transmission-daemon/settings.json
sed -i -e "\
  s|\$downcompletesed|""$downcomplete""|g; \
  s|\$downincompletesed|""$downincomplete""|g; \
  s|\$transmissionpass|""$transmissionpass""|g" \
/var/lib/transmission/.config/transmission-daemon/settings.json
chown -R transmission:transmission /var/lib/transmission/
cat ./Configs/download-unrar.sh >/usr/local/bin/download-unrar.sh
mkdir -p /etc/systemd/system/transmission-daemon.service.d
echo -e "[Service]\nUser=transmission" >/etc/systemd/system/transmission-daemon.service.d/run-as-user.conf

# Setup cleanup of transmission downloads
apt-get -y install sendmail
cat ./Configs/download-cleanup.sh >/usr/local/bin/download-cleanup.sh
sed -i -e "\
  s|\$transmissionpasssed|""$transmissionpass""|g; \
  s|\$emailsed|""$email""|g; \
  s|\$fromsed|""$from""|g" \
/usr/local/bin/download-cleanup.sh
echo "@daily root /usr/local/bin/download-cleanup.sh >/dev/null 2>&1" >/etc/cron.d/download-cleanup

# Get required packages for Sonarr, Radarr and Jackett
apt-get -y install mono-devel mediainfo sqlite3

# Install Plex
su $user -P -c 'bash -c "$(wget -qO - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)"'

# Install & configure sonarr
( cd /tmp || return
wget http://download.sonarr.tv/v2/master/mono/NzbDrone.master.tar.gz
tar -zxf /tmp/NzbDrone.master.tar.gz -C /opt/ )
mv /opt/NzbDrone /opt/nzbdrone
cat ./Configs/sonarr.service >/etc/systemd/system/sonarr.service
mkdir -p /var/lib/sonarr/.config/NzbDrone/
echo -e "<Config>\n  <UrlBase>/sonarr</UrlBase>\n</Config>" >/var/lib/sonarr/.config/NzbDrone/config.xml
chown -R sonarr:sonarr /opt/nzbdrone /var/lib/sonarr

# Install and configure radarr
( cd /tmp || return
wget --content-disposition 'http://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64'
tar -zxf Radarr*.linux-core-x64.tar.gz -C /opt/ )
mv /opt/Radarr /opt/radarr
cat ./Configs/radarr.service >/etc/systemd/system/radarr.service
mkdir -p /var/lib/radarr/.config/Radarr
echo -e "<Config>\n  <UrlBase>/radarr</UrlBase>\n</Config>" >/var/lib/radarr/.config/Radarr/config.xml
chown -R radarr:radarr /opt/radarr /var/lib/radarr

# Install & configure jackett
( cd /tmp || return
curl -s https://api.github.com/repos/Jackett/Jackett/releases | grep "browser_download_url".*Jackett.Binaries.LinuxAMDx64.tar.gz | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i-
tar -zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/ )
mv /opt/Jackett /opt/jackett
cat ./Configs/jackett.service >/etc/systemd/system/jackett.service
mkdir -p /var/lib/jackett/.config/Jackett
echo -e "{\n  \"BasePathOverride\": \"/jackett\"\n}" >/var/lib/jackett/.config/Jackett/ServerConfig.json
chown -R jackett:jackett /opt/jackett /var/lib/jackett

# Jackett updater
cat ./Configs/jackett-update.sh >/usr/local/bin/jackett-update.sh
sed -i -e "\
  s|\$emailsed|""$email""|g; \
  s|\$fromsed|""$from""|g" \
/usr/local/bin/jackett-update.sh
echo "@weekly root /usr/local/bin/jackett-update.sh >/dev/null 2>&1" >/etc/cron.d/jackett-update

# Everything in /usr/local/bin made to be executable
chmod +x /usr/local/bin/*

# Start services
systemctl restart systemd-resolved \
                  nginx
systemctl enable  transmission-daemon \
                  sonarr \
                  radarr \
                  jackett --now

printf "Setup complete.\n"
