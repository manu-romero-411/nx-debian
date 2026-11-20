#!/bin/sh
# Runs inside the rootfs, for the retrobox variant only, once the user exists
# and the Retrobox packages are installed.
#
# Creates /retrobox, the data directory of Retrobox (config/overlay/retrobox
# points data_dir there, and the configuration and the logs go there too),
# owned by the user of the image and its group. Then
# puts in it what Retrobox would download on its first start (the names are in
# /tmp/nxd-preload: theme, bezels, shaders), and records that it was offered,
# so the first start has nothing left to fetch.
set -eu

data=/retrobox
list=/tmp/nxd-preload

name="$(getent passwd 1000 | cut -d: -f1 || true)"
mkdir -p "${data}"
if [ -z "${name}" ]; then
    echo "10-retrobox-data: warning: no user with uid 1000 (--no-user?): ${data} stays root's" >&2
    rm -f "${list}"
    exit 0
fi
group="$(id -gn "${name}")"
home="$(getent passwd "${name}" | cut -d: -f6)"
chown "${name}:${group}" "${data}"
chmod 755 "${data}"

if [ -s "${list}" ]; then
    # Retrobox's own downloader, as the user it is for: the files end up with
    # the right owner and in the directories it really uses. The module is
    # run directly, not through `retrobox --download`: that option exists
    # only in newer releases, and in 0.6 `retrobox` with an unknown option
    # starts EmulationStation.
    # shellcheck disable=SC2046 # the names are words, one per line
    runuser -u "${name}" -- env HOME="${home}" PYTHONPATH=/opt/retrobox/lib \
        RETROBOX_CONFIGDIR="${data}/config" RETROBOX_STATEDIR="${data}" \
        python3 -m retrobox.startup.downloads $(cat "${list}")
    # "once" packages (bezels, shaders) are offered at the first start unless
    # they are recorded as offered: pending() records them.
    runuser -u "${name}" -- env HOME="${home}" PYTHONPATH=/opt/retrobox/lib \
        RETROBOX_CONFIGDIR="${data}/config" RETROBOX_STATEDIR="${data}" \
        python3 -c 'from retrobox.startup.downloads import pending; pending()'
fi
rm -f "${list}"
chown -R "${name}:${group}" "${data}" "${home}"
