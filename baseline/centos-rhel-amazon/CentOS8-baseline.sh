#!/bin/bash
# Baseline setup for systemd based Linux distributions
# Tested for compatibility with: CentOS 8

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

# Make /tmp temp filesystem
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Set timezone and ntp
timedatectl set-timezone $timezone
timedatectl set-ntp true

# Set hostname
echo "$hostname" > /etc/hostname
hostname $hostname

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config
systemctl reload sshd

# Configure SSH firewall rules
sed -i -e "s/AllowZoneDrifting=.*/AllowZoneDrifting=no/g"
firewall-cmd --permanent --zone=drop --change-interface=eth0
firewall-cmd --permanent --zone=drop --add-rich-rule="
  rule family=\"ipv4\"
  source address=\"$sship\"
  port protocol=\"tcp\"
  port=\"22\"
  accept"
firewall-cmd --reload
systemctl restart firewalld

# Configure .bashrc & .nanorc
cat ./Configs/root_bashrc >/root/.bashrc
cat ./Configs/nanorc >/etc/nanorc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
for dir in $(ls -d /home/*/)
do
    cat ./Configs/user_bashrc >${dir}/.bashrc
done

# Create users & passwords
for name in $users ; do
    useradd -m "$name"
    echo -e "Password for $name\n"
    passwd "$name"
done

# Add sudoers with password auth required for elevation
for name in $sudoers ; do
    echo "$name ALL=(ALL) ALL" >/etc/sudoers.d/"$name"
done