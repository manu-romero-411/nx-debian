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
check_not "retrobox has no XFCE" has_line "${RETROBOX}" "xfce4-session"
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
check_not "unknown variant is refused" "${NXD}" rootfs --variant nope --dry-run --output "${tmp}/out"
check_not "unknown command is refused" "${NXD}" frobnicate

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
