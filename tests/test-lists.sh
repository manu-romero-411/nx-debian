#!/usr/bin/env bash
# Offline tests of the package lists, the config and the mmdebstrap command.
# No network, no root, no mmdebstrap needed.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
export NXD_ROOT
NXD="${NXD_ROOT}/nxd"
# shellcheck source=../scripts/lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${NXD_ROOT}/scripts/lib/common.sh"
load_config

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
}
# check DESCRIPTION COMMAND...: passes when the command succeeds.
check() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        ok "${description}"
    else
        bad "${description}"
    fi
}
# check_not DESCRIPTION COMMAND...: passes when the command fails.
check_not() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        bad "${description}"
    else
        ok "${description}"
    fi
}

has_line() { grep -qxF -- "$2" <<< "$1"; }

XFCE="$("${NXD}" packages xfce)"
RETROBOX="$("${NXD}" packages retrobox)"

check "xfce has the desktop" has_line "${XFCE}" "xfce4-session"
check "xfce has the pinned Xorg" has_line "${XFCE}" "xserver-xorg-core"
check "retrobox has openbox" has_line "${RETROBOX}" "openbox"
check "retrobox has lightdm" has_line "${RETROBOX}" "lightdm"
check_not "retrobox has no XFCE" has_line "${RETROBOX}" "xfce4-session"
check "retrobox logs into Openbox" test "$(variant_setting retrobox NXD_AUTOLOGIN_SESSION)" = "openbox"
check "xfce logs into XFCE" test "$(variant_setting xfce NXD_AUTOLOGIN_SESSION)" = "xfce"
check "retrobox has a default user" test "$(variant_setting retrobox NXD_DEFAULT_USER)" = "retrobox"
check "retrobox has a default password" test "$(variant_setting retrobox NXD_DEFAULT_PASSWORD)" = "retrobox"
check "retrobox installs the retrobox releases" test "$(variant_setting retrobox NXD_RELEASE_LIST)" = "retrobox"
check "the retrobox release list names the four components" test "$(grep -c '^RetroboxProject/' "${NXD_ROOT}/config/releases/retrobox.list")" -eq 4
check "retrobox starts retrobox with Openbox" grep -qx 'retrobox &' "${NXD_ROOT}/config/overlay/retrobox/etc/skel/.config/openbox/autostart"
check "retrobox keeps ssh off" grep -q 'ssh.service' <(variant_setting retrobox NXD_DISABLE_UNITS)
check "xfce has no release list" test -z "$(variant_setting xfce NXD_RELEASE_LIST)"
check "the hostname is nintendo-switch" grep -qx 'nintendo-switch' "${NXD_ROOT}/config/overlay/common/etc/hostname"
check "ssh is in every variant" has_line "${RETROBOX}" "openssh-server"
check_not "xfce has no openbox" has_line "${XFCE}" "openbox"
check "both variants have the L4T BSP" has_line "${RETROBOX}" "switch-bsp"

duplicates="$(sort <<< "${XFCE}" | uniq -d)"
if [[ -z "${duplicates}" ]]; then
    ok "xfce has no duplicate packages"
else
    bad "xfce has duplicates: ${duplicates}"
fi

# Every package of a list is a plain name.
bad_names="$(grep -vE '^[a-z0-9][a-z0-9+.-]*$' <<< "${XFCE}${RETROBOX:+$'\n'}${RETROBOX}" || true)"
if [[ -z "${bad_names}" ]]; then
    ok "package names are plain"
else
    bad "odd package names: ${bad_names}"
fi

# read_list: comments and blank lines
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
printf 'a\n# comment\n\n  b  # trailing\nc' > "${tmp}/t.list"
if [[ "$(read_list "${tmp}/t.list" | tr '\n' ' ')" == "a b c " ]]; then
    ok "read_list skips comments and blanks"
else
    bad "read_list skips comments and blanks"
fi

# The pinned key matches its fingerprint, and a wrong one is refused.
check "L4T key matches its fingerprint" verify_key "${NXD_L4T_KEY}" "${NXD_L4T_KEY_FPR}"
check_not "a wrong fingerprint is refused" \
    bash -c ". '${NXD_ROOT}/scripts/lib/common.sh'; verify_key '${NXD_L4T_KEY}' 0000000000000000000000000000000000000000"

# Pins carry the repository's host.
check "pins name the L4T host" \
    grep -q 'Pin: origin "theofficialgman.github.io"' <(render_pins "$(url_host "${NXD_L4T_URL}")")
check "file: URLs pin the empty origin" \
    grep -q 'Pin: origin ""' <(render_pins "$(url_host file:///tmp/repo)")

# The compat suite
check "compat pins allow the listed packages" \
    grep -q -A2 '^Package: libpcre3$' <(render_compat_pins)
check "compat pins never pick anything else" \
    grep -q 'Pin-Priority: -1' <(render_compat_pins)
check "compat source file names the suite" \
    grep -q 'Suites: bookworm' <(compat_sources_file arm64)
check "compat off prints nothing" \
    test -z "$(NXD_COMPAT_SUITE="" render_compat_pins)$(NXD_COMPAT_SUITE="" compat_sources_file arm64)"
check "joystick is pinned to L4T" grep -q 'xserver-xorg-input-joystick' "${NXD_CONFIG_DIR}/apt/l4t.pref"

# The rootfs report, on a hand-made tarball
mkdir -p "${tmp}/fake/var/lib/dpkg" "${tmp}/fake/etc" "${tmp}/out/xfce"
printf 'Package: heavy\nStatus: install ok installed\nInstalled-Size: 2048\nDepends: lib (>= 1)\n\nPackage: lib\nStatus: install ok installed\nInstalled-Size: 10\n\nPackage: xserver-xorg-core\nStatus: install ok installed\nInstalled-Size: 1\nDepends: heavy\n' \
    > "${tmp}/fake/var/lib/dpkg/status"
mkdir -p "${tmp}/fake/usr/lib/modules/4.9.140-l4t"
# shellcheck disable=SC2016
printf 'root:!:1:0:99999:7:::\nmanu:%s:1:0:99999:7:::\n' '$6$x' > "${tmp}/fake/etc/shadow"
printf 'root:x:0:0:root:/root:/bin/bash\nmanu:x:1000:1000::/home/manu:/bin/bash\n' > "${tmp}/fake/etc/passwd"
: > "${tmp}/fake/etc/machine-id"
tar -C "${tmp}/fake" -cf "${tmp}/out/xfce/rootfs.tar" .
REPORT="$("${NXD}" inspect --variant xfce --output "${tmp}/out" --why lib)"
check "report lists the heaviest package" grep -q '2.0 MiB  heavy' <<< "${REPORT}"
check "report explains who pulls a package in" grep -q 'lib (pulled in): heavy' <<< "${REPORT}"
check "report sees the empty machine-id" grep -q 'machine-id empty: True' <<< "${REPORT}"
check "report names the chain that brought a package in" grep -q 'lib <- heavy <- xserver-xorg-core' <<< "${REPORT}"
check "report reads the kernel version" grep -q 'kernel versions: 4.9.140-l4t' <<< "${REPORT}"
check "report shows the password state" grep -q 'root uid=0 .*(locked)' <<< "${REPORT}"
check "report sees a set password" grep -q 'manu uid=1000 .*(password set)' <<< "${REPORT}"
chmod 555 "${tmp}/out/xfce"
check "report survives an unwritable output dir" "${NXD}" inspect --variant xfce --output "${tmp}/out"
chmod 755 "${tmp}/out/xfce"
check_not "report refuses a missing rootfs" "${NXD}" inspect --variant retrobox --output "${tmp}/out"

# The mmdebstrap command
DRY="$("${NXD}" rootfs --variant retrobox --dry-run --output "${tmp}/out")"
check "dry run builds a minbase" grep -q -- '--variant=minbase' <<< "${DRY}"
check "dry run targets arm64" grep -q -- '--architectures=arm64' <<< "${DRY}"
check "dry run skips Recommends" grep -q 'Install-Recommends' <<< "${DRY}"
check "dry run installs the L4T source and its key" \
    grep -q 'nxd-l4t.sources' <<< "${DRY}"
check "dry run installs the L4T key" grep -q 'theofficialgman-L4T.asc' <<< "${DRY}"
check "L4T source file has the key and the component" \
    grep -q 'Signed-By: /etc/apt/keyrings/k.asc' <(l4t_sources_file arm64 /etc/apt/keyrings/k.asc noble)
check "L4T source file honours the component" \
    grep -q 'Components: jammy' <(l4t_sources_file arm64 /etc/apt/keyrings/k.asc jammy)
check "dry run runs the hooks" grep -q '10-machine-id.sh' <<< "${DRY}"
check "retrobox does not ship docs or kernel headers" grep -q 'dpkg.cfg.d' <<< "${DRY}"
check "dpkg excludes list the headers" grep -q 'path-exclude=/usr/src/linux-headers-\*' <(dpkg_excludes_file retrobox)
check "retrobox masks the apt timers" grep -q 'apt-daily.timer' <(variant_setting retrobox NXD_MASK_UNITS)
check "retrobox keeps NetworkManager" test -z "$(variant_setting retrobox NXD_MASK_UNITS | grep -i 'networkmanager\|bluetooth\|pulse' || true)"
check "dpkg excludes are not expanded as globs" test "$(dpkg_excludes_file retrobox | wc -l)" -le 8
check "dpkg excludes keep the copyright files" grep -q 'path-include=/usr/share/doc/\*/copyright' <(dpkg_excludes_file retrobox)
check "xfce has no dpkg excludes" test -z "$(dpkg_excludes_file xfce)"
check "a user is staged by --user" grep -q 'nxd-user' <("${NXD}" rootfs --variant xfce --user manu --no-password --dry-run --output "${tmp}/out")
check_not "a bad login name is refused" "${NXD}" rootfs --variant xfce --user 'Bad Name' --no-password --dry-run --output "${tmp}/out"
check_not "--no-password needs --user" "${NXD}" rootfs --variant xfce --no-password --dry-run --output "${tmp}/out"
check "retrobox dry run needs no prompt for its user" "${NXD}" rootfs --variant retrobox --dry-run --output "${tmp}/out" < /dev/null
check_not "an empty --releases-dir is refused" "${NXD}" rootfs --variant retrobox --dry-run --releases-dir "${tmp}" --output "${tmp}/out"
check "--no-releases is accepted" "${NXD}" rootfs --variant retrobox --no-releases --dry-run --output "${tmp}/out" < /dev/null
check "--no-user is accepted" "${NXD}" rootfs --variant retrobox --no-user --no-releases --dry-run --output "${tmp}/out" < /dev/null
check "--user takes the password from NXD_PASSWORD" env NXD_PASSWORD=x "${NXD}" rootfs --variant xfce --user manu --dry-run --output "${tmp}/out"
check_not "unknown variant is refused" "${NXD}" rootfs --variant nope --dry-run --output "${tmp}/out"
check_not "unknown command is refused" "${NXD}" frobnicate

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
