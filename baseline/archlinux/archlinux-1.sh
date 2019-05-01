#!/bin/bash
# Setup a non-encrypted base install of Arch
swapsize="16896" # Size of required swap in MiB + 512
installdrive="sda" # Drive to install Arch on (e.g. "$installdrive")


# Set time & keyboard map
timedatectl set-ntp true
loadkeys uk.map.gz

# Sort the mirrorlist so downloads are fast enough
grep --no-group-separator -A1 "United Kingdom" /etc/pacman.d/mirrorlist > /mirrorlist
cat /mirrorlist > /etc/pacman.d/mirrorlist

# Install git (if this script has been copy/pasted)
pacman -Sy && pacman -S git --noconfirm

# Create partitions, create and open encrypted volume and mount all partitions
parted -s /dev/"$installdrive" mklabel gpt
parted -s /dev/"$installdrive" mkpart ESP fat32 2048s 512MiB
parted -s /dev/"$installdrive" set 1 boot on
parted -s /dev/"$installdrive" mkpart primary ext4 512MiB "$swapsize"MiB
parted -s /dev/"$installdrive" mkpart primary ext4 "$swapsize"MiB 100%

mkfs.vfat -F32 /dev/"$installdrive"1
mkswap /dev/"$installdrive"2
mkfs.ext4 /dev/"$installdrive"3

mount /dev/"$installdrive"3 /mnt
mkdir /mnt/boot
mount /dev/"$installdrive"1 /mnt/boot
swapon /dev/"$installdrive"2

# Install base system
pacstrap /mnt base base-devel openssh wget git haveged

# Copy mirrorlist to installed base system
cp /mirrorlist /mnt/etc/pacman.d/
genfstab -pU /mnt >> /mnt/etc/fstab

# Set /tmp as temp drive
echo "tmpfs	/tmp tmpfs defaults,noatime,mode=1777 0 0" >> /mnt/etc/fstab

# Clone the deploy repo to the new install and chroot in to run next script
cat ./Configs/strap.sh >/mnt/strap.sh
(cd /mnt || return
git clone https://github.com/colinjmatt/deploys)
sed -i -e "s/installdrive=\"\"/installdrive=installdrive=\"""$installdrive=""\"/g" /mnt/deploys/baseline/archlinux/archlinux-2.sh
nano /mnt/deploys/baseline/archlinux/archlinux-2.sh
chmod +x /mnt/deploys/baseline/archlinux/archlinux-2.sh /mnt/strap.sh

arch-chroot /mnt ./strap.sh

# Unmount and reboot into installed system
umount -R /mnt
swapoff -a
reboot
