#!/bin/bash
# Setup an encrypted base install of Arch

# Set time & keyboard map
timedatectl set-ntp true
loadkeys uk.map.gz

# Sort the mirrorlist so downloads are fast enough
grep --no-group-separator -A1 "United Kingdom" /etc/pacman.d/mirrorlist > /mirrorlist
cat /mirrorlist > /etc/pacman.d/mirrorlist

# Create partitions, create and open encrypted volume and mount all partitions
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart ESP fat32 2048s 512MiB
parted -s /dev/sda set 1 boot on
parted -s /dev/sda mkpart primary ext4 512MiB 100%
mkfs.vfat -F32 /dev/sda1

cryptsetup luksFormat /dev/sda2
cryptsetup luksOpen /dev/sda2 sda2-crypt

pvcreate /dev/mapper/sda2-crypt
vgcreate vg0 /dev/mapper/sda2-crypt
lvcreate -L 2G vg0 -n swap
lvcreate -l 100%FREE vg0 -n root
mkswap /dev/mapper/vg0-swap
mkfs.ext4 /dev/mapper/vg0-root

mount /dev/mapper/vg0-root /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
swapon /dev/mapper/vg0-swap

# Install base system
pacstrap /mnt base base-devel linux openssh wget nano git haveged

# Copy mirrorlist to installed base system
cp /mirrorlist /mnt/etc/pacman.d/
genfstab -pU /mnt >> /mnt/etc/fstab

# Set /tmp as temp drive
echo "tmpfs	/tmp tmpfs defaults,noatime,mode=1777 0 0" >> /mnt/etc/fstab

# Chroot in
arch-chroot /mnt

# Unmount and reboot into installed system
umount -R /mnt
swapoff -a
reboot
