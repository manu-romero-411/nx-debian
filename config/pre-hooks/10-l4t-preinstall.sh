#!/bin/sh
# Runs inside the rootfs, before the packages are installed. Both L4T packages
# below assume they are installed on a running console and need a flag to
# know they are being installed into an image:
#
# * nvidia-l4t-ccp-*: the preinst reads /etc/nv_boot_control.conf and refuses
#   to install where there is no Tegra boot control. NVIDIA's flag file makes
#   it skip that step.
# * switch-bsp: the postinst mounts the boot partition (/dev/mmcblk0p1) and
#   copies the boot files into it, unless /opt/switchroot/image_prep exists.
#   It also writes into /etc/apport/blacklist.d, which must exist.
#
# The flags are removed again by config/hooks/05-l4t-postinstall.sh.
#
# A variant without L4T packages (/tmp/nxd-packages is its package list)
# needs none of this.
set -eu

grep -qE '^(switch-bsp|nvidia-l4t-)' /tmp/nxd-packages || exit 0

mkdir -p /opt/nvidia/l4t-packages
touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall
mkdir -p /opt/switchroot
touch /opt/switchroot/image_prep
mkdir -p /etc/apport/blacklist.d
