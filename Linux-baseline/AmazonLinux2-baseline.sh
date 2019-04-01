#!/bin/bash
# Amazon Linux 2 instance baseline setup for init.d or systemd based Linux distributions
# Compatible with CentOS 7

# Name of the server
hostname="example-server"
# FQDN of the server
domain="example.com"
# List of user accounts to create
users="user1 user2 user3 user4 user5"
# List of the above users allowed to SSH to the server
sshusers="user1 user3"
# List of users to become sudoers
sudoers="user1 user4"

# Firwalld is needed
yum install firewalld -y

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

# Set hostname
echo "$hostname" > /etc/hostname
hostname $hostname

# Configure SSH
cat ./sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config
systemctl reload sshd

# Configure SSH firewall rules
systemctl start firewalld
firewall-cmd --permanent --zone=public --change-interface=eth0
firewall-cmd --permanent --zone=public --add-port=22/tcp

# Configure .bashrc
cat ./root_bashrc >/root/.bashrc
cat ./user_bashrc >/etc/skel/.bashrc

# Optimise motd if Amazon Linux
if uname -r | grep amzn; then
    update-motd --disable
    cat ./motd >/etc/motd
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
