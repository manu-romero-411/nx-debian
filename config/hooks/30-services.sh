#!/bin/sh
# Runs inside the rootfs. Masks the units a variant does not want
# (NXD_MASK_UNITS in config/variants/*.conf; the list comes in /tmp/nxd-mask,
# one unit per line, and is deleted here).
set -eu

list=/tmp/nxd-mask
[ -f "${list}" ] || exit 0
while IFS= read -r unit; do
    [ -n "${unit}" ] || continue
    # Drop the links that enabled it, then point the unit name at /dev/null.
    find /etc/systemd -name "${unit}" -type l -delete
    ln -s /dev/null "/etc/systemd/system/${unit}"
done < "${list}"
rm -f "${list}"
