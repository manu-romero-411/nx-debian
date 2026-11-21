#!/bin/sh
# Runs inside the rootfs, once the user exists (20-user.sh): the polkit rule of
# the Retrobox console for that user (retrobox-polkit-rule, from
# retrobox-system-settings): power off and reboot, and set the time zone and
# the keyboard layout from EmulationStation (retrobox-system-settings), with
# no password. Without a user, or without that package, there is no rule.
set -eu

user="$(getent passwd 1000 | cut -d: -f1)"
if [ -z "${user}" ]; then
    echo "30-retrobox-polkit: no user (uid 1000): no polkit rule" >&2
    exit 0
fi
if ! command -v retrobox-polkit-rule > /dev/null 2>&1; then
    echo "30-retrobox-polkit: warning: no retrobox-polkit-rule (retrobox-system-settings is not installed): no polkit rule" >&2
    exit 0
fi
mkdir -p /etc/polkit-1/rules.d
retrobox-polkit-rule "${user}" > /etc/polkit-1/rules.d/50-retrobox-console.rules
chmod 644 /etc/polkit-1/rules.d/50-retrobox-console.rules
