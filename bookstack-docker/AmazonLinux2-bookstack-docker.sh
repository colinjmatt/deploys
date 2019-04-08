#!/bin/bash
# Bookstack docker deployment using Amazon Linux 2
# Set the domain name to be used BEFORE running this script
domain="example.com"
# Name of the user that the docker container will be run as (user must exist)
dockeruser="ec2-user"

# Install required packages
yum install docker git -y
nginx=$(amazon-linux-extras list | grep nginx | awk -F ' ' '{print $2}')
amazon-linux-extras install "$nginx" -y

( cd /tmp || return
curl -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install epel-release-latest-7.noarch.rpm )
yum install certbot

# Enable and start docker and add user to group
systemctl enable docker --now
usermod -aG docker "$dockeruser" # Logout required after this step

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Bookstack docker image
( cd "$dockeruser" || exit
git clone https://github.com/solidnerd/docker-bookstack.git )

# Edit /home/"$dockeruser"/docker-bookstack/docker-compose.yml to use latest tag
sed -i -e "s/image\:\ solidnerd\/bookstack\:.*/image\: solidnerd\/bookstack\:latest/g" /home/"$dockeruser"/docker-bookstack/docker-compose.yml/docker-compose.yml

# Create docker-bookstack service and enable it
cp ./Configs/docker-bookstack.service /etc/systemd/system/docker-bookstack.service
systemctl enable docker-bookstack --now

# Configure nginx pre certbot
mkdir -p /var/www/docker-bookstack/.well-known
mkdir -p /etc/nginx/sites
cp ./Configs/nginx.conf /etc/nginx/nginx.conf
cp ./Configs/docker-bookstack-pre-certbot.conf /etc/nginx/sites/docker-bookstack.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/docker-bookstack.conf

# Start nginx
systemctl enable nginx --now

# Configure certbot
certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /var/www/docker-bookstack -d "$domain"

# Configure nginx for SSL with port 80 redirect and reload
cp ./Configs/docker-bookstack-post-certbot.conf /etc/nginx/sites/docker-bookstack.conf
sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/docker-bookstack.conf
systemctl reload nginx
