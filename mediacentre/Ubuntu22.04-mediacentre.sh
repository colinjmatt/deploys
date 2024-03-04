#!/bin/bash
# Media server deployment using Ubuntu 22.04

domain="example.com" # FQDN of the server
user="user1" # Name of non-root user to install Plex as (usually the user you will ssh with)
transmissionpass='password' # Password for transmission rpc (needs to be single-quoted)
transmissionwhitelist='example.com' # Address to whitelist
basemediapath='Media' # This MUST match all other locations below
downcomplete='Downloads/Complete' # Location of completed downloads
downincomplete='Downloads/Incomplete' # Location of incomplete downloads
tv='TV-Shows' # Location of TV shows
films='Films' # Location of films

# Create download directories
mkdir -p /"$basemediapath"/{"$downcomplete"/{"$films","$tv"},"$downincomplete","$films","$tv"}
chmod 777 "$basemediapath"
chmod -R 770 "$basemediapath"/*

# Ensure permissions for downloads and media are set... permissively
cat ./Configs/permissions.sh >/usr/local/bin/permissions.sh
echo "*/5 * * * * root /usr/local/bin/permissions.sh" >/etc/cron.d/permissions
sed -i -e "\
  s|\$tv|\/""$basemediapath""\/""$tv""|g; \
  s|\$films|\/""$basemediapath""\/""$films""|g; \
  s|\$downcomplete|\/""$basemediapath""\/""$downcomplete""|g; \
  s|\$downcomplete|\/""$basemediapath""\/""$downincomplete""|g" \
/usr/local/bin/permissions.sh

# Create service users
users="transmission sonarr radarr jackett flaresolverr"
for name in $users ; do
    groupadd -r "$name"
    useradd -m -r -g "$name" -d /var/lib/"$name" -s /usr/sbin/nologin "$name"
    chown -R "$name":"$name" /var/lib/"$name"
    usermod -a -G transmission "$name"
done

# Use Cloudflare DNS
echo "DNS=1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4" >> /etc/systemd/resolved.conf
systemctl restart systemd-resolved

# Add firewall rules
# 80     http
# 443    https
# 9091   transmission rpc (only if a remote client is to be used to access transmission)
# 32400  plex
# 55369  transmission
ports="80 443 9091 32400 55369"
for port in $ports; do
    firewall-cmd --permanent --zone=drop --add-port="$port"/tcp
done
firewall-cmd --reload

# Install & configure nginx with certbot certs
apt-get -y install nginx certbot
mkdir -p /usr/share/nginx/html/.well-known
rm /etc/nginx/sites-enabled/default
chmod 0750 /usr/share/nginx/html/.well-known/
cat ./Configs/nginx.conf >/etc/nginx/nginx.conf
cat ./Configs/pre-certbot.conf >/etc/nginx/sites-available/mediacentre.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites-available/mediacentre.conf
useradd -r nginx
systemctl enable nginx --now
certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /usr/share/nginx/html -d "$domain"
cat ./Configs/post-certbot.conf >/etc/nginx/sites-available/mediacentre.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites-available/mediacentre.conf
ln -sf /etc/nginx/sites-available/mediacentre.conf /etc/nginx/sites-enabled/mediacentre.conf
cat ./Configs/certbot-auto >/usr/local/bin/certbot-auto
echo "@daily root /usr/local/bin/certbot-auto >/dev/null 2>&1" >/etc/cron.d/certbot

# Make front page
mkdir -p /var/www/root
cp ./Homepage/* /var/www/root/

# Generate Diffie Hellman
openssl dhparam -out /etc/ssl/dhparams.pem 4096

# Install & configure transmission-daemon
apt-get -y install transmission-daemon rar unrar
mkdir -p /var/lib/transmission/.config/transmission-daemon/
cat ./Configs/settings.json >/var/lib/transmission/.config/transmission-daemon/settings.json
sed -i -e "\
  s|\$downcomplete|\/""$basemediapath""\/""$downcomplete""|g; \
  s|\$downincomplete|\/""$basemediapath""\/""$downincomplete""|g; \
  s|\$transmissionpass|""$transmissionpass""|g; \
  s|\$transmissionwhitelist|""$transmissionwhitelist""|g" \
/var/lib/transmission/.config/transmission-daemon/settings.json
chown -R transmission:transmission /var/lib/transmission/ /Media/Downloads
cat ./Configs/download-unrar.sh >/usr/local/bin/download-unrar.sh
mkdir -p /etc/systemd/system/transmission-daemon.service.d
echo -e "[Service]\nUser=transmission" >/etc/systemd/system/transmission-daemon.service.d/run-as-user.conf

# Setup cleanup of transmission downloads
apt-get -y install sendmail
cat ./Configs/download-cleanup.sh >/usr/local/bin/download-cleanup.sh
sed -i -e "\
  s|transmissionpass-sed|\/""$basemediapath""\/""$transmissionpass""|g; \
  s|downloads-sed|\/""$basemediapath""\/""$downcomplete""|g" \
/usr/local/bin/download-cleanup.sh
echo "@daily root /usr/local/bin/download-cleanup.sh >/dev/null 2>&1" >/etc/cron.d/download-cleanup

# Get required packages for Sonarr, Radarr and Jackett
apt-get -y install mono-devel mediainfo sqlite3

# Install Plex
su $user -P -c 'bash -c "$(wget -qO - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)"'
usermod -a -G sonarr,radarr plex

# SWITCHING TO JELLYFIN MAYBE #
# Install Jellyfin
curl https://repo.jellyfin.org/install-debuntu.sh | bash
usermod -a -G sonarr,radarr jellyfin

# Install & configure sonarr
apt-get -y install software-properties-common
# New key add script needed, but this still works for now
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8
echo "deb https://apt.sonarr.tv/ubuntu focal main" | sudo tee /etc/apt/sources.list.d/sonarr.list
apt-get update && apt-get install sonarr
sed -i -e "s/<UrlBase>.*/<UrlBase>\/sonarr<\/UrlBase>/g" /var/lib/sonarr/config.xml
chown -R sonarr:sonarr /var/lib/sonarr /"$basemediapath"/"$tv"

# Install and configure radarr
( cd /tmp || return
wget --content-disposition 'http://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64'
tar -zxf Radarr*.linux-core-x64.tar.gz -C /opt/ )
mv /opt/Radarr /opt/radarr
cat ./Configs/radarr.service >/etc/systemd/system/radarr.service
mkdir -p /var/lib/radarr/.config/Radarr
echo -e "<Config>\n  <UrlBase>/radarr</UrlBase>\n</Config>" >/var/lib/radarr/.config/Radarr/config.xml
chown -R radarr:radarr /opt/radarr /var/lib/radarr /"$basemediapath"/"$films"

# Install & configure jackett
( cd /tmp || return
curl -s https://api.github.com/repos/Jackett/Jackett/releases | grep "browser_download_url.*Jackett.Binaries.LinuxAMDx64.tar.gz" | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i-
tar -zxf Jackett.Binaries.LinuxAMDx64.tar.gz -C /opt/ )
mv /opt/Jackett /opt/jackett
cat ./Configs/jackett.service >/etc/systemd/system/jackett.service
mkdir -p /var/lib/jackett/.config/Jackett
echo -e "{\n  \"BasePathOverride\": \"/jackett\"\n}" >/var/lib/jackett/.config/Jackett/ServerConfig.json
chown -R jackett:jackett /opt/jackett /var/lib/jackett

# Jackett updater
cat ./Configs/jackett-update.sh >/usr/local/bin/jackett-update.sh
echo "@weekly root /usr/local/bin/jackett-update.sh >/dev/null 2>&1" >/etc/cron.d/jackett-update

# Install flaresolverr
# These dependencies required once a precompiled release for v3 is available
# apt-get -y install chromium-browser xvfb python3-pip

apt-get -y install firefox libgtk-3-0 libasound2 libx11-xcb1
( cd /tmp || return
curl -s https://api.github.com/repos/FlareSolverr/FlareSolverr/releases | grep "browser_download_url.*flaresolverr-.*-linux-x64.zip" | head -1 | cut -d : -f 2,3 | tr -d \" | wget -i-
unzip flaresolverr-*-linux-x64.zip -d /opt/ )
cp ./Configs/flaresolverr.service /etc/systemd/system/
chown -R flaresolverr:flaresolverr /opt/flaresolverr /var/lib/flaresolverr

# Install and configure fail2ban
apt-get -y install fail2ban
cat ./Configs/fail2ban.local >/etc/fail2ban/fail2ban.local
cat ./Configs/jail.local >/etc/fail2ban/jail.local
cat ./Configs/jellyfin.conf >/etc/fail2ban/fail2ban.d/jellyfin.conf

# Everything in /usr/local/bin made to be executable
chmod +x /usr/local/bin/*

# Start services
systemctl restart systemd-resolved \
                  nginx
systemctl enable  transmission-daemon \
                  sonarr \
                  radarr \
                  jackett \
                  jellyfin \
                  flaresolverr --now

printf "Setup complete.\n"
