#!/usr/bin/env bash
# Test of the choice of the SD card's partition in nxd-sdcard (--pick), with
# the output of `lsblk -bnP -o NAME,PKNAME,FSTYPE,SIZE` of several cards.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
SCRIPT="${NXD_ROOT}/packages/nxd-retrobox/root/usr/sbin/nxd-sdcard"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export NXD_SDCARD_NO_PROBE=1

# pick DESCRIPTION WANT DISK: the partition chosen from ${tmp}/lsblk ("" = none)
pick() {
    local description="$1" want="$2" disk="$3" got
    got="$(sh "${SCRIPT}" --pick "${disk}" "${tmp}/lsblk" || true)"
    if [[ "${got}" == "${want}" ]]; then ok "${description}"; else bad "${description}: got '${got}', want '${want}'"; fi
}

# the usual card: FAT32 first, then the image's ext4
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0" PKNAME="" FSTYPE="" SIZE="512110190592"
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="137438953472"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
LSBLK
pick "the FAT32 partition of the boot disk" mmcblk0p1 mmcblk0

# not the first partition, not mmcblk0p1: no number is assumed
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0" PKNAME="" FSTYPE="" SIZE="512110190592"
NAME="mmcblk0p3" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
NAME="mmcblk0p7" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="137438953472"
NAME="mmcblk0p8" PKNAME="mmcblk0" FSTYPE="" SIZE="4194304"
LSBLK
pick "whatever number it has" mmcblk0p7 mmcblk0

# another disk with FAT32 (a USB stick) is not the card
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="sda" PKNAME="" FSTYPE="" SIZE="64000000000"
NAME="sda1" PKNAME="sda" FSTYPE="vfat" SIZE="64000000000"
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="137438953472"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
LSBLK
pick "the boot disk's, not a USB stick's" mmcblk0p1 mmcblk0
pick "without the boot disk: the biggest of all" mmcblk0p1 ""

# the label does not matter, spaces in it neither
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="137438953472" LABEL="MI TARJETA SD"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360" LABEL="NXDEB"
LSBLK
pick "a label with spaces" mmcblk0p1 mmcblk0

# two FAT32 partitions (without hekate's folders to look for): the biggest
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="1073741824"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="137438953472"
NAME="mmcblk0p3" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
LSBLK
pick "the biggest of two" mmcblk0p2 mmcblk0

# exFAT only
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="exfat" SIZE="137438953472"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
LSBLK
pick "exFAT when there is no FAT32" mmcblk0p1 mmcblk0

# FAT32 before a bigger exFAT
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="exfat" SIZE="137438953472"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="vfat" SIZE="1073741824"
LSBLK
pick "FAT32 before exFAT" mmcblk0p2 mmcblk0

# nothing to mount
cat > "${tmp}/lsblk" << 'LSBLK'
NAME="mmcblk0p1" PKNAME="mmcblk0" FSTYPE="ntfs" SIZE="137438953472"
NAME="mmcblk0p2" PKNAME="mmcblk0" FSTYPE="ext4" SIZE="16106127360"
LSBLK
pick "neither FAT32 nor exFAT: nothing" "" mmcblk0

# the unit and the script
# what broke on the console: lsblk refuses -r together with -P
if grep -q 'lsblk -b[a-z]*r[a-z]*P\|lsblk -b[a-z]*P[a-z]*r' "${SCRIPT}"; then bad "lsblk without -r next to -P"; else ok "lsblk without -r next to -P"; fi
if grep -q 'iocharset=utf8' "${SCRIPT}"; then bad "no iocharset=utf8 (no nls_utf8 in L4T)"; else ok "no iocharset=utf8 (no nls_utf8 in L4T)"; fi
if [[ -x "${SCRIPT}" ]]; then ok "the script is executable"; else bad "the script is executable"; fi
unit="${NXD_ROOT}/packages/nxd-retrobox/root/usr/lib/systemd/system/nxd-sdcard.service"
if grep -qx 'ExecStart=/usr/sbin/nxd-sdcard' "${unit}"; then ok "the unit runs the script"; else bad "the unit runs the script"; fi
# shellcheck disable=SC2016 # the literal text of the script
if grep -q 'deb-systemd-helper enable "${unit}"' "${NXD_ROOT}/packages/nxd-retrobox/DEBIAN/postinst" &&
    grep -qx 'unit=nxd-sdcard.service' "${NXD_ROOT}/packages/nxd-retrobox/DEBIAN/postinst"; then
    ok "the package enables the unit"
else
    bad "the package enables the unit"
fi
if grep -qx 'Before=systemd-user-sessions.service display-manager.service lightdm.service graphical.target' "${unit}"; then
    ok "it is mounted before any login, and unmounted after every session"
else
    bad "it is mounted before any login, and unmounted after every session"
fi
# what left the console at the text login: lightdm waited for a whole check of
# a 512 GB card after a shutdown that had not unmounted it
if grep -qx 'TimeoutStartSec=4min' "${unit}"; then ok "the session never waits for ever"; else bad "the session never waits for ever"; fi
# shellcheck disable=SC2016 # the literal text of the script
if grep -q 'timeout "${NXD_SDCARD_FSCK_TIMEOUT:-120}" fsck.vfat -a' "${SCRIPT}"; then ok "the check has a time limit"; else bad "the check has a time limit"; fi
# shellcheck disable=SC2016 # the literal text of the script
if grep -q 'mount -o remount,ro "${mountpoint}"' "${SCRIPT}"; then ok "a busy card is made read-only at shutdown"; else bad "a busy card is made read-only at shutdown"; fi
if grep -qw psmisc "${NXD_ROOT}/packages/nxd-retrobox/DEBIAN/control.in"; then ok "fuser is there for it"; else bad "fuser is there for it"; fi

# the dirty bit: byte 0x41 of a FAT32 boot sector, 0x25 of a FAT16 one
fat="$(mktemp)"
head -c 512 /dev/zero > "${fat}"
dirtycheck() {
    local name="$1" want="$2"
    shift 2
    if "${SCRIPT}" --dirty "${fat}" "$@"; then got=0; else got=1; fi
    if [[ "${got}" -eq "${want}" ]]; then ok "${name}"; else bad "${name}"; fi
}
dirtycheck "a clean FAT32 is not checked" 1 FAT32
printf '\001' | dd of="${fat}" bs=1 seek=65 conv=notrunc status=none
dirtycheck "a dirty FAT32 is" 0 FAT32
dirtycheck "...and its bit is not FAT16's" 1 FAT16
printf '\003' | dd of="${fat}" bs=1 seek=37 conv=notrunc status=none
dirtycheck "a dirty FAT16 is" 0 FAT16
dirtycheck "an unknown FAT is checked" 0 ""
rm -f "${fat}"

printf '%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
