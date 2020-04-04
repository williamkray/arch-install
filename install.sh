#!/usr/bin/env bash

set -euo pipefail

## installs arch linux on a device
## intended to be run from the arch live ISO
## this script is extremely destructive, run with caution

## TODO:
## add more of my preferred packages out of the box
## include initial user setup steps
## include installation of yay from aur
## include list of packages to install from aur with yay
## update inotify watch count
## update swappiness

## sets environment variables to be used by an arch installation
INSTALL_DISK="/dev/sda"
INSTALL_PKGS="base \
  base-devel \
  linux \
  linux-firmware \
  linux-lts \
  linux-headers \
  linux-lts-headers \
  docker \
  docker-compose \
  openssh \
  scrot \
  imagemagick \
  xorg-server \
  xorg-server-devel \
  xorg-xsetroot \
  ttf-dejavu \
  rsync \
  mutt \
  pcmanfm \
  gimp \
  firefox \
  tmux \
  vim \
  go \
  rofi \
  unclutter \
  arandr \
  wireless_tools \
  wpa_supplicant \
  dhcpcd \
  inetutils \
  netctl \
  intel-ucode \
  cmus \
  efibootmgr \
  alsa-utils \
  pulseaudio-alsa \
  pavucontrol \
  pulseaudio \
  pulseaudio-bluetooth \
  ifplugd \
  xorg-xinit \
  xautolock \
  i3lock \
  feh \
  virtualbox \
  virtualbox-host-modules-arch \
  wget \
  curl \
  git"
TIMEZONE="America/Los_Angeles"
HOSTNAME="testhost"
USERNAME="wreck"
INSTALL_AUR_PKGS="bitwarden-cli \
  bitwarden-bin \
  ttf-google-fonts-git \
  keybase-bin"


## define things
## set other variables
root_mountpoint="/mnt"
boot_mountpoint="${root_mountpoint}/boot"
## change-root and install various system configurations
_chroot() {
  arch-chroot ${root_mountpoint} $*
}

echo "setting time"
timedatectl set-ntp true

## create partitions as such:
## 512M /boot
## the rest /
## optimize alignment for partitions
echo "creating partitions with parted"
parted --script -a opt -- ${INSTALL_DISK} \
  mklabel gpt \
  mkpart boot fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart root ext4 512MiB 100%

## create our encrypted root volume
## and decrypt it
echo "creating encrypted root volume"
cryptsetup -y -v luksFormat ${INSTALL_DISK}2

echo "decrypting root volume"
cryptsetup open ${INSTALL_DISK}2 cryptroot

## make filesystems
echo "formatting filesystems"
mkfs.fat -F32 ${INSTALL_DISK}1
mkfs.ext4 /dev/mapper/cryptroot
# save uuid for later
cryptuuid=$(blkid -s UUID -o value ${INSTALL_DISK}2)

## mount partitions appropriately
echo "mounting filesystems for installation at $root_mountpoint"
mkdir -p $root_mountpoint
mount /dev/mapper/cryptroot $root_mountpoint
mkdir -p $boot_mountpoint
mount ${INSTALL_DISK}1 $boot_mountpoint

## create swapfile, comment out if not needed
echo "creating swapfile"
dd if=/dev/zero of=${root_mountpoint}/swapfile bs=1M count=4096 status=progress
chmod 600 ${root_mountpoint}/swapfile
mkswap ${root_mountpoint}/swapfile
swapon ${root_mountpoint}/swapfile

## rank pacman mirrors by speed and location
echo "installing rankmirrors and setting up pacman mirror list"
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
pacman -Sy --noconfirm pacman-contrib
curl -s "https://www.archlinux.org/mirrorlist/?country=US&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

## run installation
echo "installing packages"
pacstrap $root_mountpoint $INSTALL_PKGS

## generate fstab
echo "generating fstab"
genfstab -U ${root_mountpoint} >> ${root_mountpoint}/etc/fstab


pushd ${root_mountpoint}
echo "setting timezone to $TIMEZONE"
ln -sf /usr/share/zoneinfo/${TIMEZONE} etc/localtime
echo "fixing locale"
sed -i 's/^#en_US/en_US/g' etc/locale.gen
echo "setting language"
echo 'LANG=en_US.UTF-8' > etc/locale.conf
echo "setting hostname to $HOSTNAME"
echo ${HOSTNAME} > etc/hostname
echo "writing hostsfile"
cat << EOF > /etc/hosts
127.0.0.1     localhost   ${HOSTNAME}
::1           localhost   ${HOSTNAME}
EOF
echo "writing mkinitcpio.conf file"
cp etc/mkinitcpio.conf{,.backup}
echo 'MODULES=()' > etc/mkinitcpio.conf
echo 'BINARIES=()' >> etc/mkinitcpio.conf
echo 'FILES=()' >> etc/mkinitcpio.conf
echo 'HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)' >> etc/mkinitcpio.conf
popd

echo "setting system clock"
_chroot hwclock --systohc
echo "generating locales"
_chroot locale-gen
echo "generating initramfs"
_chroot mkinitcpio -P
echo "setting root password"
_chroot passwd
echo "installing systemd-boot"
_chroot bootctl --path=/boot install
cat << EOF > ${boot_mountpoint}/loader/loader.conf
timeout 3
default arch
auto-entries 1
editor 0
EOF

echo "writing systemd-boot entries"
cat << EOF > ${boot_mountpoint}/loader/entries/arch.conf
title Arch Linux (Standard Kernel)
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options cryptdevice=UUID=${cryptuuid}:cryptroot root=/dev/mapper/cryptroot rw
EOF

cat << EOF > ${boot_mountpoint}/loader/entries/arch-lts.conf
title Arch Linux (LTS Kernel)
linux /vmlinuz-linux-lts
initrd /intel-ucode.img
initrd /initramfs-linux-lts.img
options cryptdevice=UUID=${cryptuuid}:cryptroot root=/dev/mapper/cryptroot rw
EOF

echo "identifying network devices"
eth0=$(ip link show | grep en | head -1 | awk -F ': ' '{print $2}')
wlan0=$(ip link show | grep wl | head -1 | awk -F ': ' '{print $2}') || wlan=""

echo "creating netctl ethernet profile"
cat << EOF > ${root_mountpoint}/etc/netctl/ethernet-dhcp
Description='A basic dhcp ethernet connection'
Interface=${eth0}
Connection=ethernet
IP=dhcp
EOF

echo "enabling network at boot"
_chroot systemctl enable netctl-ifplugd@${eth0}

if [[ -n $wlan0 ]]; then
  _chroot systemctl enable netctl-auto@${wlan0}
fi

echo "creating user ${USERNAME}"
_chroot useradd -mU -d /home/${USERNAME} -G wheel,docker,vboxusers,input ${USERNAME}
_chroot passwd ${USERNAME}

echo "editing sudoers file"
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' ${root_mountpoint}/etc/sudoers

echo "configuring user profile"
wget -O ${root_mountpoint}/home/${USERNAME}/init.sh https://raw.githubusercontent.com/williamkray/scripts/master/init.sh
chmod +x ${root_mountpoint}/home/${USERNAME}/init.sh
pushd ${root_mountpoint}/home/${USERNAME}
git clone https://aur.archlinux.org/yay.git
echo "$INSTALL_AUR_PKGS" > aur-pkgs
_chroot chown -R ${USERNAME}.${USERNAME} /home/${USERNAME}
#_chroot sudo su - ${USERNAME} bash ~/init.sh


echo "done"
