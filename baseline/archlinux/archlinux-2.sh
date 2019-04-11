#!/bin/bash
hostname="" # single
users="user1 user2" # multiple
sshusers="user1 user2" # multiple
domain="localdomain" # single
ipaddress="0.0.0.0/0" # single
dns="'0.0.0.0' '0.0.0.0'" # single quoted multiples
gateway="0.0.0.0" # single

# Set region and locale
rm /etc/localtime
ln -s /usr/share/zoneinfo/Europe/London /etc/localtime
echo "en_GB.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
export LANG=en_GB.UTF-8
echo "KEYMAP=uk" > /etc/vconsole.conf

# Create dhcp ethernet connection
cat ./Configs/ethernet-static >/etc/netctl/ethernet-static
sed -i -e "\
    s/\$interface/""$(ls /sys/class/net/ | grep "^en")""/g
    s/\$ipaddress/""$ipaddress""/g; \
    s/\$gateway/""$gateway""/g; \
    s/\$dns/""$dns""/g; \
    s/\$domain/""$domain""/g" \
/etc/netctl/ethernet-static

# Set hostname
hostname $hostname
echo "$hostname" > /etc/hostname
echo "127.0.0.1 localhost.localdomain localhost $hostname" > /etc/hosts

# Configure pacman
cat ./Configs/pacman.conf >/etc/pacman.conf

# Set .bashrc  and .nanorc for users & root
cat ./Configs/root_bashrc >/root/.bashrc
cat ./Configs/user_bashrc >/etc/skel/.bashrc
cat ./Configs/root_nanorc >/root/.nanorc
cat ./Configs/user_nanorc >/etc/skel/.nanorc
cat ./Configs/nanorc > /etc/nanorc

# Set root password, create user, add to sudoers and set password
passwd root

for name in $users ; do
    groupadd $name
    useradd -m -g $name -G users,wheel,storage,power $name
    passwd $name
done

for name in $sudoers ; do
    echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/$name
    chmod 0400 /etc/sudoers.d/$name
done

# Add modules and hooks to mkinitcpio and generate
sed -i "s/MODULES=.*/MODULES=(nls_cp437 vfat)/g" /etc/mkinitcpio.conf
sed -i "s/HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard)/g" /etc/mkinitcpio.conf
mkinitcpio -p linux

# Setup bootctl
bootctl install
mkdir -p /etc/pacman.d/hooks
cat ./Configs/100-systemd-boot.hook >/etc/pacman.d/hooks/100-systemd-boot.hook
cat ./Configs/loader.conf >/boot/loader/loader.conf
cat ./Configs/arch.conf >/boot/loader/entries/arch.conf
luksencryptuuid=$(blkid | grep crypto_LUKS | awk -F '"' '{print $2}')
sed -i -e "s/\$luksencryptuuid/""$luksencryptuuid""/g" /boot/loader/entries/arch*.conf

# Install & configure reflector
cat ./Configs/10-mirrorupgrade.hook >/etc/pacman.d/hooks/10-mirrorupgrade.hook
cat ./Configs/reflector.service >/etc/systemd/system/reflector.service
cat ./Configs/reflector.timer >/etc/systemd/system/reflector.timer
echo "COUNTRY=UK" > /etc/conf.d/reflector.conf
systemctl enable reflector.timer

# Config for vfio reservation, blacklist nVidia driver and quiet kernel
echo "kernel.printk = 3 3 3 3" > /etc/sysctl.d/20-quiet-printk.conf

# Setup fsck after kernel load due to being removed for quiet boot
cat ./Configs/systemd-fsck-root.service >/etc/systemd/system/systemd-fsck-root.service
cat ./Configs/systemd-fsck\@.service >/etc/systemd/system/systemd-fsck\@.service

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config

# Set locale
localectl set-keymap uk
localectl set-locale LANG="en_GB.UTF-8"

# Set time synchronisation
timedatectl set-ntp true

# Enable and start networking to download more packages
systemctl enable netctl
netctl enable ethernet-dhcp

# Enable ssh to assist with rest of setup
systemctl enable sshd

# Exit chroot
exit
