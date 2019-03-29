#!/bin/bash
# AWS Lightsail OpenVPN Server Setup on Amazon Linux

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

# Install packages
yum-config-manager --enable epel
yum install openvpn easy-rsa mailx -y

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

# Configure easy-rsa
mkdir -p /etc/easy-rsa
cp -r /usr/share/easy-rsa/3.0.*/* /etc/easy-rsa
cat ./Configs/vars >/etc/easy-rsa/vars

# Generate Diffie Hellman & HMAC
mkdir -p /etc/openvpn/server
openssl dhparam -out /etc/openvpn/server/dh.pem 2048
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Initialise PKI
(
cd /etc/easy-rsa || return
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
)
# Enable ip forwarding & firewall hardening rules
sed -i -e "s/net.ipv4.ip_forward.*/net.ipv4.ip_forward\ =\ 1/g" /etc/sysctl.conf
cat ./Configs/iptables-config >/etc/sysconfig/iptables-config

touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
modprobe iptable_nat
echo 1 | tee /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -s 10.8.0.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 10.8.1.0/24 -j MASQUERADE
iptables -P INPUT DROP
iptables -A INPUT -i eth0 -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p udp --dport 1194 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp -s "$sship" --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
/etc/init.d/iptables save

# Openvpn conifguration
cat ./Configs/tcpserver.conf >/etc/openvpn/tcpserver.conf
cat ./Configs/udpserver.conf >/etc/openvpn/udpserver.conf

# Client .ovpn profile
mkdir -p /etc/openvpn/template-profiles
mkdir -p /etc/openvpn/client-profiles
cat ./Configs/profile.ovpn >/etc/openvpn/template-profiles/profile.ovpn
sed -i -e "s/\$domain/""$domain""/g" /etc/openvpn/template-profiles/profile.ovpn

# Copy cert & ovpn profile generator script
cat ./Configs/gen-ovpn >/usr/local/bin/gen-ovpn
chmod +x /usr/local/bin/gen-ovpn

# Start and enable openvpn
/etc/init.d/network restart
chkconfig openvpn on
/etc/init.d/openvpn start

# TODO
# Create script for on-demand revocation
# cd /etc/easy-rsa
# ./easyrsa revoke $VPNCLIENT
# ./easyrsa gen-crl
# cp /etc/easy-rsa/pki /etc/openvpn/server/
# sed -i -e "s/.*crl-verify.*/crl-verify\ \/etc\/openvpn\/server\/crl.pem/g"/etc/openvpn/server/server.conf

printf "Setup complete.\n"
printf "\033[0;31m\x1b[5m**REBOOT THIS INSTANCE FROM THE AWS CONSOLE\!**\x1b[25m\n"
