#!/bin/bash
# Baseline setup for init.d based Linux distributions
# Tested for compatibility with: CentOS 6
#                                Amazon Linux

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
# Name of your timezone which can be found in /usr/share/zoneinfo/
timezone="Europe/London"

# Packages needed
yum install ntp ntpdate -y

# Create 2GB swapfile
dd if=/dev/zero of=/mnt/swapfile bs=1M count=2048
chown root:root /mnt/swapfile
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
echo "/mnt/swapfile swap swap defaults 0 0" >> /etc/fstab
swapon -a

# Make /tmp temp filesystem
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Set timezone and ntp
rm /etc/localtime
ln -s /usr/share/zoneinfo/Europe/London /etc/localtime

# Set hostname
echo "$hostname" > /etc/hostname
hostname $hostname

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config
/etc/init.d/sshd reload

# Configure SSH firewall rules
iptables -P INPUT DROP
iptables -A INPUT -i eth0 -p tcp -s "$sship" --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Only necessary if you want to alias mail to send to another server/external recipient
iptables -A INPUT -p tcp -s localhost --dport 25 -j ACCEPT
/etc/init.d/iptables save

# Configure .bashrc & .nanorc
cat ./Configs/root_bashrc >/root/.bashrc
cat ./Configs/root_nanorc >/root/.nanorc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/user_nanorc >/etc/skel/.nanorc
for dir in $(ls -d /home/*)
do
    cat ./Configs/user_bashrc >${dir}/.bashrc
    cat ./Configs/user_nanorc >${dir}/.nanorc
done

# Optimise motd if Amazon Linux
if uname -r | grep amzn; then
    update-motd --disable
    cat ./Configs/motd >/etc/motd
    sed -i -e "s/\$domain/""$domain""/g" /etc/motd
fi

# Create users & passwords
for name in $users ; do
    useradd -m "$name"
    echo "Password for $name"
    passwd "$name"
done

# Add sudoers with password auth required for elevation
for name in $sudoers ; do
    echo "$name ALL=(ALL) ALL" >/etc/sudoers.d/"$name"
done
