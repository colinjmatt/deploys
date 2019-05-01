#!/bin/bash
installdrive="sda" # Drive to Arch is installed on (e.g. "sda")
hostname="localhost" # single value
users="user1 user2" # multiple values
sudoers="user1 user2" # multiple values
sshusers="user1 user2" # multiple values
domain="localdomain" # single value
ipaddress="0.0.0.0\/24" # single value, backslash is intentional
dns="'0.0.0.0' '0.0.0.0'" # single-quoted multiple values
gateway="0.0.0.0" # single value

# Set region and locale
rm /etc/localtime
ln -s /usr/share/zoneinfo/Europe/London /etc/localtime
echo "en_GB.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
export LANG=en_GB.UTF-8
echo "KEYMAP=uk" > /etc/vconsole.conf

# Create dhcp ethernet connection
# $interface may be better expressed at echo /sys/class/net/en* | cut -d "/" -f 2 | xargs printf "/%s"
# old expression is ls /sys/class/net/ | grep "^en"
cat ./Configs/ethernet-static >/etc/netctl/ethernet-static
sed -i -e "s/\$interface/""$(echo /sys/class/net/en* | cut -d / -f 5 | xargs printf %s)""/g; \
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
echo -e "Password for root\n"
passwd root

for name in $users ; do
    groupadd "$name"
    useradd -m -g "$name" -G users,wheel,storage,power "$name"
    echo -e "Password for $name\n"
    passwd "$name"
done

for name in $sudoers ; do
    echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/"$name"
    chmod 0400 /etc/sudoers.d/"$name"
done

# Add modules and hooks to mkinitcpio and generate
for drive in /dev/mapper/vg*; do
  if [[ -e "$drive" ]]; then
  sed -i -e "s/MODULES=.*/MODULES=(nls_cp437 vfat)/g; \
             s/HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard)/g" \
             /etc/mkinitcpio.conf
  else
    sed -i -e "s/HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard)/g" /etc/mkinitcpio.conf
  fi
done
mkinitcpio -p linux

# Setup bootctl
bootctl install
mkdir -p /etc/pacman.d/hooks
cat ./Configs/100-systemd-boot.hook >/etc/pacman.d/hooks/100-systemd-boot.hook
cat ./Configs/loader.conf >/boot/loader/loader.conf
cat ./Configs/arch.conf >/boot/loader/entries/arch.conf

for drive in /dev/mapper/vg*; do
  if [[ -e "$drive" ]]; then
    luksencryptuuid=$(blkid | grep crypto_LUKS | awk -F '"' '{print $2}')
    sed -i -e "s/\$uuid/cryptdevice=UUID=""$luksencryptuuid"":""$installdrive""2-crypt:allow-discards root=\/dev\/mapper\/vg0-root\ rd.luks.options=discard/g" /boot/loader/entries/arch*.conf
  else
    uuid=$(blkid | grep "$installdrive"3 | awk -F '"' '{print $2}')
    sed -i -e "s/\$uuid/root=UUID=""$uuid""/g" /boot/loader/entries/arch*.conf
  fi
done

# Install & configure reflector
pacman -S reflector --noconfirm
cat ./Configs/10-mirrorupgrade.hook >/etc/pacman.d/hooks/10-mirrorupgrade.hook
cat ./Configs/reflector.service >/etc/systemd/system/reflector.service
cat ./Configs/reflector.timer >/etc/systemd/system/reflector.timer
systemctl enable reflector.timer

# Config for vfio reservation, blacklist nVidia driver and quiet kernel
echo "kernel.printk = 3 3 3 3" > /etc/sysctl.d/20-quiet-printk.conf

# Setup fsck after kernel load due to being removed for quiet boot
cat ./Configs/systemd-fsck-root.service >/etc/systemd/system/systemd-fsck-root.service
cat ./Configs/systemd-fsck\@.service >/etc/systemd/system/systemd-fsck\@.service

# Configure SSH
cat ./Configs/sshd_config >/etc/ssh/sshd_config
sed -i -e "s/\$sshusers/""$sshusers""/g" /etc/ssh/sshd_config

# Install & configure nfs-utils
pacman -S --noconfirm nfs-utils
sed -i -e "s/#Domain\ =/Domain\ =\ ""$domain""/g" /etc/idmapd.conf

# Set locale
localectl set-keymap uk
localectl set-locale LANG="en_GB.UTF-8"

# Set time synchronisation
timedatectl set-ntp true

# Enable services
systemctl enable  haveged \
                  netctl \
                  sshd

# Enable networking
netctl enable ethernet-static

# Cleanup
rm -rf /deploys /strap.sh

# Exit chroot
exit 0
