#!/bin/bash
# AWS Lightsail Transmission Server Setup on Amazon Linux
hostname="example-server"
domain="example.com"
users="user1 user2 user3 user4 user5"
sshusers="user1 user3" # List of the above users allowed to SSH to the server
sship="0.0.0.0/0" # Change if SSH access should be restricted to an IP or IP range
sudoers="user1 user4" # List of users to become sudoers

# Install packages
yum install transmission-daemon -y

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
iptables -A INPUT -i eth0 -p tcp -s "$sship" --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
/etc/init.d/iptables save

# TODO
# The actual setup of transmission and flexget

/etc/init.d/network restart
