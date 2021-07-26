#!/bin/bash
# Baseline setup for systemd based Linux distributions
# Tested for compatibility with: Ubuntu 20.04

# Name of the server
hostname="example-server"
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
apt-get -y install firewalld

# Create 4GB swapfile
dd if=/dev/zero of=/mnt/swapfile bs=1M count=4096
chown root:root /mnt/swapfile
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
echo "/mnt/swapfile swap swap defaults 0 0" >> /etc/fstab
swapon -a

# Make /tmp temp filesystem
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Set timezone and ntp
timedatectl set-timezone $timezone
timedatectl set-ntp true

# Set hostname
echo "$hostname" > /etc/hostname
hostname $hostname

# Disable IPv6
echo "net.ipv6.conf.all.disable_ipv6=1" >/etc/sysctl.d/10-ipv6.conf

# Configure .bashrc & .nanorc
cat ./Configs/root_bashrc >/root/.bashrc
cat ./Configs/nanorc >/etc/nanorc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
for dir in $(ls -d /home/*/); do
  cat ./Configs/user_bashrc >"${dir}"/.bashrc
done

# Create users & passwords
for name in $users ; do
  useradd -m "$name" -s /bin/bash
  echo -e "Password for $name\n"
  passwd "$name"
done

# Add sudoers with password auth required for elevation
for name in $sudoers ; do
  echo "$name ALL=(ALL) ALL" >/etc/sudoers.d/"$name"
done
