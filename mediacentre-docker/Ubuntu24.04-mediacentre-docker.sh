#!/bin/bash
# Dockerised media server deployment using Ubuntu 24.04

# Domain name
domain="example.com"

# Sonarr/Radarr API keys (if known)
radarr_api_key="abcdefg1234567890abcdefg1234567890a"
sonarr_api_key="abcdefg1234567890abcdefg1234567890a"

# SMB credentials
smbuser="user"
smbpassword="password"
smburl='example.com/shared'

# Transmission credentials
transmission_user="user"
transmission_pass="1234"

# Wireguard settings
wireguard_private_key=""
wireguard_addresses=""
wireguard_server_countries=""

# Add Docker repo
apt-get -y install apt-transport-https
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update && apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Test Docker is setup properly
docker run hello-world

# Set up media directory/share (assuming an SMB share)
mkdir -p /mnt/media/{blackhole,downloads/{incomplete,complete/{tv-sonarr,films-radarr}},films,tv}
echo "$smbuser" >/root/.SMBcredentials
echo "$smbpassword" >>/root/.SMBcredentials
chmod 400 /root/.SMBcredentials
mount -t cifs -o rw,vers=3.0,credentials=/root/.SMBcredentials //"$smburl"/backup /mnt/media
echo "//$smburl /mnt/media cifs credentials=/root/.SMBcredentials,uid=1000,gid=1000,file_mode=0775,dir_mode=0775 0 0" >> /etc/fstab

# Setup Nginx
cat ./Configs/nginx-pre-certbot.conf >/opt/mediacentre/nginx/nginx.conf
sed -i -e "s/\$domain/""$domain""/g" /opt/mediacentre/nginx/nginx.conf
mkdir -p /opt/mediacentre/nginx/html/.well-known

# Generate Diffie Hellman
openssl dhparam -out /opt/mediacentre/nginx/dhparam.pem 4096

# Docker compose file
cat ./Configs/docker-compose.yml >/opt/mediacentre/docker-compose.yml
sed -i -e "s/\$domain/""$domain""/g" /opt/mediacentre/docker-compose.yml

# Start Docker to generate initial config files
( cd /opt/mediacentre || return
docker compose up -d 
docker compose down)

# Config file adjustments
cat ./Configs/download-unrar.sh >/opt/mediacentre/transmission/download-unrar.sh
chmod +x /opt/mediacentre/transmission/download-unrar.sh
sed -i -e "s/<UrlBase>.*/<UrlBase>\/sonarr<\/UrlBase>/g" /opt/mediacentre/sonarr/config.xml
sed -i -e "s/<UrlBase>.*/<UrlBase>\/radarr<\/UrlBase>/g" /opt/mediacentre/radarr/Radarr/config.xml
sed -i \
    -e "s/\"BasePathOverride\":.*/\"BasePathOverride\": \"\/jackett\",/" \
    -e "s/\"BaseUrlOverride\":.*/\"BaseUrlOverride\": \"https:\/\/$domain\",/" \
/opt/mediacentre/jackett/Jackett/ServerConfig.json
sed -i \
    -e 's|"dht-enabled".*|"dht-enabled": false,|' \
    -e 's|"idle-seeding-limit".*|"idle-seeding-limit": 28800,|' \
    -e 's|"idle-seeding-limit-enabled".*|"idle-seeding-limit-enabled": true,|' \
    -e 's|"script-torrent-done-enabled".*|"script-torrent-done-enabled": true,|' \
    -e 's|"script-torrent-done-filename".*|"script-torrent-done-filename": "/config/download-unrar.sh",|' \
/opt/mediacentre/transmission/settings.json
chmod 600 /opt/mediacentre/.env

# Install & configure certbot certs
apt-get -y install certbot
certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /opt/mediacentre/nginx/html -d "$domain"
cat ./Configs/certbot-auto >/usr/local/bin/certbot-auto
chmod +x /usr/local/bin/certbot-auto
echo "@daily root /usr/local/bin/certbot-auto >/dev/null 2>&1" >/etc/cron.d/certbot
cat ./Configs/nginx-post-certbot.conf >/opt/mediacentre/nginx/nginx.conf
sed -i -e "s/\$domain/""$domain""/g" /opt/mediacentre/nginx/nginx.conf

# Add API key variables
echo "radarr_api_key=$radarr_api_key" >/opt/mediacentre/.env
echo "sonarr_api_key=$sonarr_api_key" >/opt/mediacentre/.env

# Add Transmission credentials
echo "transmission_user=$transmission_user" >/opt/mediacentre/.env
echo "transmission_pass=$transmission_pass" >/opt/mediacentre/.env

# Configure Gluetun with Wireguard details:
echo "wireguard_private_key=$wireguard_private_key" >/opt/mediacentre/.env
echo "wireguard_addresses=$wireguard_addresses" >/opt/mediacentre/.env
echo "wireguard_server_countries=$wireguard_server_countries" >/opt/mediacentre/.env

# Start Docker again
( cd /opt/mediacentre || return
docker compose up -d )