#!/bin/sh
# Runs inside the rootfs. Masks and disables the units a variant does not
# want. The lists come in /tmp/nxd-mask and /tmp/nxd-disable (one unit per
# line; NXD_MASK_UNITS and NXD_DISABLE_UNITS in config/variants/*.conf) and
# are deleted here.
#
# Masked: cannot be started at all. Disabled: not started at boot, but one
# `systemctl enable --now` away.
set -eu

list=/tmp/nxd-mask
if [ -f "${list}" ]; then
    while IFS= read -r unit; do
        [ -n "${unit}" ] || continue
        # Drop the links that enabled it, then point the unit name at /dev/null.
        find /etc/systemd -name "${unit}" -type l -delete
        ln -s /dev/null "/etc/systemd/system/${unit}"
    done < "${list}"
    rm -f "${list}"
fi

list=/tmp/nxd-disable
if [ -f "${list}" ]; then
    while IFS= read -r unit; do
        [ -n "${unit}" ] || continue
        find /etc/systemd -name "${unit}" -type l -delete
    done < "${list}"
    rm -f "${list}"
fi
