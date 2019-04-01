#!/bin/bash
# Bookstack docker deployment using Amazon Linux 2
# Set the domain name to be used BEFORE running this script
domain="example.com"

# Check if this block has already been done
if [ -f /tmp/bookstack-install ]; then
    rm /tmp/bookstack-install
else
  touch /tmp/bookstack-install
	# Install required packages
	sudo yum install docker git

	nginx=$(amazon-linux-extras list | grep nginx | awk -F ' ' '{print $2}')
	sudo amazon-linux-extras install "$nginx" -y

	cd /tmp || exit
	curl -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	sudo yum install epel-release-latest-7.noarch.rpm
	sudo yum install certbot

	# Enable and start docker and add user to group
	sudo systemctl enable docker --now
	sudo usermod -aG docker ec2-user # Logout required after this step
	echo "This script will now log you out. Log back in as $USER and run this script again to continue"
	sleep 10
	exit
fi

# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Bookstack docker image
cd ~ || exit
git clone https://github.com/solidnerd/docker-bookstack.git

# Edit /home/ec2-user/docker-bookstack/docker-compose.yml to use latest tag
sed -i -e "s/image\:\ solidnerd\/bookstack\:.*/image\: solidnerd\/bookstack\:latest/g" docker-compose.yml

# Create docker-bookstack service and enable it
sudo cp ./Configs/docker-bookstack.service /etc/systemd/system/docker-bookstack.service
sudo systemctl enable docker-bookstack --now

# Configure nginx pre certbot
sudo mkdir -p /var/www/docker-bookstack/.well-known
sudo mkdir -p /etc/nginx/sites
sudo cp ./Configs/nginx.conf /etc/nginx/nginx.conf
sudo cp ./Configs/docker-bookstack-pre-certbot.conf /etc/nginx/sites/docker-bookstack.conf
sudo sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/docker-bookstack.conf

# Start nginx
sudo systemctl enable nginx --now

# Configure certbot
sudo certbot certonly --agree-tos --register-unsafely-without-email --webroot -w /var/www/docker-bookstack -d "$domain"

# Configure nginx for SSL with port 80 redirect and reload
sudo cp ./Configs/docker-bookstack-post-certbot.conf /etc/nginx/sites/docker-bookstack.conf
sudo sed -i -e "s/\$domain/""$domain""/g" /etc/nginx/sites/docker-bookstack.conf
sudo systemctl reload nginx
