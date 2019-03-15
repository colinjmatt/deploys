#!/bin/bash
# AWS Lightsail OpenVPN Server Setup on Amazon Linux
HOSTNAME=example-server
USERS="user1 user2 user3 user4 user5"
SSHUSERS="user1 user3" # List of the above users allowed to SSH to the server
SUDOERS="user1 user4" # List of users to become sudoers

# Install packages
cd /tmp || exit
curl -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install epel-release-latest-7.noarch.rpm

yum install openvpn easy-rsa -y

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
sed -i -e "s/HOSTNAME=.*/HOSTNAME=""$HOSTNAME""/g" /etc/sysconfig/network
hostname $HOSTNAME

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$SSHUSERS/""$SSHUSERS""/g"
/etc/init.d/sshd reload

# Configure .bashrc
cat ./Configs/root_bashrc >>/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/user_bashrc >/home/ec2-user/.bashrc

# Optimise motd
update-motd --disable
cat ./Configs/motd >/etc/motd

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

# Configure easy-rsa
mkdir -p /etc/easy-rsa
cp –r /usr/share/easy-rsa/3.0.3/* /etc/easy-rsa
cat ./Configs/vars >/etc/easy-rsa/vars

# Generate Diffie Hellman & HMAC
mkdir -p /etc/openvpn/server
openssl dhparam -out /etc/openvpn/server/dh.pem 2048
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Initialise PKI
cd /etc/easy-rsa
source ./vars
./easyrsa init-pki

# Generate ca
./easyrsa build-ca nopass
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/server

# Generate & sign server cert
./easyrsa gen-req vpn-server nopass
./easyrsa sign-req server vpn-server
cp /etc/easy-rsa/pki/private/vpn-server.key /etc/openvpn/server/
cp /etc/easy-rsa/pki/issued/vpn-server.crt /etc/openvpn/server/

# Generate & sign client cert
# TODO
# Create script to generate client certs on-demand
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1

# TODO
# Create script for on-demand revocation
# cd /etc/easy-rsa
# ./easyrsa revoke client1
# ./easyrsa gen-crl
# cp /etc/easy-rsa/pki /etc/openvpn/server/
# sed -i -e "s/.*crl-verify.*/crl-verify\ \/etc\/openvpn\/server\/crl.pem/g"/etc/openvpn/server/server.conf

# Openvpn conifguration
# /etc/openvpn/server.conf
# /etc/sysctl.conf

# Client .ovpn profile
#client
#proto udp
#remote openvpnserver.example.com
#port 1194
#dev tun
#nobind

#key-direction 1

#<ca>
#-----BEGIN CERTIFICATE-----
# insert base64 blob from ca.crt
#-----END CERTIFICATE-----
#</ca>

#<cert>
#-----BEGIN CERTIFICATE-----
# insert base64 blob from client1.crt
#-----END CERTIFICATE-----
#</cert>

#<key>
#-----BEGIN PRIVATE KEY-----
# insert base64 blob from client1.key
#-----END PRIVATE KEY-----
#</key>

#<tls-auth>
#-----BEGIN OpenVPN Static key V1-----
# insert ta.key
#-----END OpenVPN Static key V1-----
#</tls-auth>
