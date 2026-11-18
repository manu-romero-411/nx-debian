#!/bin/sh
# Runs inside the new rootfs. Every console must get its own machine-id: the
# old build shipped one fixed value in every image. An empty file makes
# systemd generate one at the first boot.
#
# systemd-firstboot would then ask for a locale and a root password on the
# console, which a Switch Lite (no keyboard) cannot answer, so it is masked.
# The first-boot setup of the image (user, password) is a separate step.
#
# Not verified on a console yet.
set -eu

: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
mkdir -p /etc/systemd/system
ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service
