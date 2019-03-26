#!/bin/bash
# AWS Lightsail Transmission Server Setup on Amazon Linux
hostname="example-server"
domain="example.com"
users="user1 user2 user3 user4 user5"
sshusers="user1 user3" # List of the above users allowed to SSH to the server
sship="0.0.0.0/0" # Change if SSH access should be restricted to an IP or IP range
sudoers="user1 user4" # List of users to become sudoers

# Install packages
# yum install transmission-daemon -y

# 2.92 (14714) is broken. 2.94 can be downloaded instead with the following:
yum remove libevent -y # Only seems to have nfs-utils as a dependency and 2.94 depends on libevent2 2.0.10
( cd /tmp || return
wget  http://geekery.altervista.org/geekery/el6/x86_64/libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-common-2.94-1.el6.geekery.x86_64.rpm \
      http://geekery.altervista.org/geekery/el6/x86_64/transmission-daemon-2.94-1.el6.geekery.x86_64.rpm

yum install libevent2-2.0.10-1.el6.geekery.x86_64.rpm \
            transmission-common-2.94-1.el6.geekery.x86_64.rpm \
            transmission-daemon-2.94-1.el6.geekery.x86_64.rpm
)

pip install --upgrade setuptools
pip install flexget

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

# Add firewall rules
touch /etc/sysconfig/iptables
chkconfig iptables on
/etc/init.d/iptables start
iptables -P INPUT DROP
iptables -A INPUT -i eth0 -p tcp --dport 9091 -m state --state NEW,ESTABLISHED -j ACCEPT
# iptables -A INPUT -i eth0 -p tcp --dport 45535 -m state --state NEW,ESTABLISHED -j ACCEPT # possibly needed for transmission port
iptables -A INPUT -i eth0 -p tcp -s "$sship" --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
/etc/init.d/iptables save

# TODO
# The actual setup of transmission and flexget
# From the wiki:
# Some Linux distributions' start script for transmission-daemon use different location.
# This varies by distribution, but two paths sometimes used are
# /var/lib/transmission-daemon and /var/run/transmission.
# https://github.com/transmission/transmission/wiki/Environment-Variables for more config

/etc/init.d/network restart
