#!/bin/sh
# Runs inside the rootfs. Creates the first user (uid 1000) when
# `nxd rootfs --user NAME` asked for one; the name and the password hash come
# in /tmp/nxd-user (two lines), which is deleted here. Without --user the
# image has no user, and the setup of the first boot has to create it.
set -eu

spec=/tmp/nxd-user
[ -f "${spec}" ] || exit 0
name="$(sed -n 1p "${spec}")"
hash="$(sed -n 2p "${spec}")"
rm -f "${spec}"

useradd --create-home --uid 1000 --user-group --shell /bin/bash "${name}"
# No hash: the account stays locked for password logins (autologin still works).
if [ -n "${hash}" ]; then
    usermod --password "${hash}" "${name}"
fi
for group in sudo audio video input render plugdev netdev bluetooth dialout; do
    if getent group "${group}" > /dev/null; then
        usermod --append --groups "${group}" "${name}"
    fi
done
