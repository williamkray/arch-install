Opinionated Arch Installation Script
====================================

This is a script to install Arch Linux in a pretty opinionated way. It does not take arguments, you must review and edit the script before running it to make sure you don't totally ruin everything in your life.

Boot the official arch installation ISO, download this script from is.gd/wreckarchinstall, change the variables, make whatever tweaks you want, and run it. By default it does this stuff:

  * install to /dev/sda (this really **really** needs to be edited to whatever disk you want to install to)
  * boot using systemd-boot (gummiboot)
  * set up a simplified partition scheme: one boot partition (512MB) and the rest is root partition
  * encrypt the root partition with LUKS
  * install a bunch of applications
  * try to find network devices and configure them to start at boot
  * create a user named `wreck` (you should probably change that to your username)
  * download my basic user account init script in the user's directory

anything you want done differently, you'll have to edit the script
