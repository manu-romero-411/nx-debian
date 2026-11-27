#!/bin/sh
# Runs inside the rootfs. Creates the first user (uid 1000) when
# `nxd rootfs --user NAME` asked for one; the name and the password hash come
# in /tmp/nxd-user (name, password hash, autologin session: one per line,
# the last two may be empty), which is deleted here. Without --user the
# image has no user, and the setup of the first boot has to create it.
set -eu

spec=/tmp/nxd-user
[ -f "${spec}" ] || exit 0
name="$(sed -n 1p "${spec}")"
hash="$(sed -n 2p "${spec}")"
session="$(sed -n 3p "${spec}")"
rm -f "${spec}"

useradd --create-home --uid 1000 --user-group --shell /bin/bash "${name}"
# No hash: the account stays locked for password logins (autologin still works).
if [ -n "${hash}" ]; then
    usermod --password "${hash}" "${name}"
fi
for group in sudo adm systemd-journal audio video input render plugdev netdev bluetooth dialout; do
    if getent group "${group}" > /dev/null; then
        usermod --append --groups "${group}" "${name}"
    fi
done

# The group whose members sudo lets update the system and install packages
# without a password (retrobox-system-settings' sudoers.d/retrobox-nopasswd).
groupadd --system --force retrobox
usermod --append --groups retrobox "${name}"
# The same for nxd-update (nxd-common's sudoers.d/nxd-update and its polkit
# rule); nxd-common made the group already.
groupadd --system --force nxd
usermod --append --groups nxd "${name}"

# Straight into the session of the variant, when there is a display manager.
if [ -n "${session}" ] && [ -d /etc/lightdm ]; then
    if [ ! -e "/usr/share/xsessions/${session}.desktop" ]; then
        echo "20-user: warning: no /usr/share/xsessions/${session}.desktop" >&2
    fi
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-nxd-autologin.conf << EOF
[Seat:*]
autologin-user=${name}
autologin-user-timeout=0
autologin-session=${session}
EOF
fi
