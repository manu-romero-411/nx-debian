#!/bin/sh
# Runs inside the rootfs, before the packages are installed.
#
# The L4T boot firmware packages (nvidia-l4t-ccp-*) read /etc/nv_boot_control.conf
# in their preinst and refuse to install where there is no Tegra boot control
# (a chroot, a build host). NVIDIA's own flag file makes them skip that step.
# It is removed again by config/hooks/05-l4t-postinstall.sh.
#
# switch-bsp's postinst fails when /etc/apport/blacklist.d does not exist.
set -eu

mkdir -p /opt/nvidia/l4t-packages
touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall
mkdir -p /etc/apport/blacklist.d
