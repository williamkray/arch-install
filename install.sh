#!/usr/bin/env bash

set -euo pipefail

## installs arch linux on a device
## intended to be run from the arch live ISO
## this script is extremely destructive, run with caution

## pull in variables 
source variables.sh

## set systemtime
timedatectl set-ntp true

## create partitions as such:
## 512M /boot
## the rest /
## optimize alignment for partitions
parted --script -a opt -- ${INSTALL_DISK} \
  mklabel gpt \
  mkpart boot fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart root ext4 512MiB 100%

## create our encrypted root volume
## and decrypt it
cryptsetup -y -v luksFormat ${INSTALL_DISK}2
cryptsetup open ${INSTALL_DISK}2 cryptroot

## make filesystems
mkfs.fat -F32 ${INSTALL_DISK}1
mkfs.ext4 /dev/mapper/cryptroot

## set other variables
root_mountpoint="/mnt"
boot_mountpoint="${root_mountpoint}/boot"

## mount partitions appropriately
mkdir -p $root_mountpoint
mount /dev/mapper/cryptroot $root_mountpoint
mount ${INSTALL_DISK}1 $boot_mountpoint

## create swapfile, comment out if not needed
dd if=/dev/zero of=${root_mountpoint}/swapfile bs=1M count=4096 status=progress
chmod 600 ${root_mountpoint}/swapfile
mkswap ${root_mountpoint}/swapfile
swapon ${root_mountpoint}/swapfile

## rank pacman mirrors by speed and location
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
pacman -Sy --noconfirm pacman-contrib
curl -s "https://www.archlinux.org/mirrorlist/?country=US&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

## run installation
pacstrap $root_mountpoint $INSTALL_PKGS

## generate fstab
genfstab -U ${root_mountpoint} >> ${root_mountpoint}/etc/fstab

## change-root and install various system configurations
_chroot() {
  arch-chroot ${root_mountpoint} $*
}

pushd ${root_mountpoint}
ln -sf usr/share/zoneinfo/${TIMEZONE} etc/localtime
sed -i 's/^#en_US/en_US/g' etc/locale.gen
echo 'LANG=en_US.UTF-8' > etc/locale.conf
echo ${HOSTNAME} > etc/hostname
cat << EOF > /etc/hosts
127.0.0.1     localhost   ${HOSTNAME}
::1           localhost   ${HOSTNAME}
EOF
cp etc/mkinitcpio.conf{.backup}
echo 'MODULES=()' > etc/mkinitcpio.conf
echo 'BINARIES()' >> etc/mkinitcpio.conf
echo 'FILES()' >> etc/mkinitcpio.conf
echo 'HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)' >> etc/mkinitcpio.conf
popd

cryptuuid=$(blkid -s UUID -o value ${INSTALL_DISK}2)
_chroot hwclock --systohc
_chroot locale-gen
_chroot mkinitcpio -P
_chroot passwd
_chroot efibootmgr --disk ${INSTALL_DISK} --part 1 --create --label "Arch Linux" --loader /vmlinuz-linux --unicode "cryptdevice=UUID=${cryptuuid}:cryptroot root=/dev/mapper/cryptroot rw initrd=/intel-ucode.img initrd=/initramfs-linux.img"
