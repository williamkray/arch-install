#!/usr/bin/env bash

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
  xorg-server-devel \
  rsync \
  pcmanfm \
  gimp \
  firefox \
  tmux \
  vim \
  rofi \
  arandr \
  wireless_tools \
  wpa_supplicant \
  dhcpcd \
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
  virtualbox-host-modules \
  git"
TIMEZONE="America/Los_Angeles"
HOSTNAME="testhost"
USERNAME="wreck"
