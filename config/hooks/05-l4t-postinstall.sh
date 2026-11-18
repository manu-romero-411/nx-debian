#!/bin/sh
# Runs inside the rootfs, right after the packages are installed: undo what
# config/pre-hooks/10-l4t-preinstall.sh needed only for the installation.
set -eu

rm -f /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall
rmdir /opt/nvidia/l4t-packages /opt/nvidia 2> /dev/null || true
# Left in place when a package put something in it (switch-bsp does).
rmdir /etc/apport/blacklist.d /etc/apport 2> /dev/null || true
