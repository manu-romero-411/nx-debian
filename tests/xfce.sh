#!/usr/bin/env bash
# Test of the tools of nxd-xfce with fake xrandr and xinput: switch-rotate's
# rotations, the touchscreen matrix, the saved state and its restore, and the
# line switch-sensors prints.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
BIN="${NXD_ROOT}/packages/nxd-xfce/root/usr/bin"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
check() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then ok "${description}"; else bad "${description}"; fi
}
check_not() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then bad "${description}"; else ok "${description}"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" "${tmp}/home"
export HOME="${tmp}/home" XDG_CONFIG_HOME="${tmp}/home/.config" CALLS="${tmp}/calls" ROT="${tmp}/rot"
echo normal > "${ROT}"

# xrandr: one screen, DSI-0, in the rotation in $ROT; --rotate changes it
cat > "${tmp}/bin/xrandr" << 'EOF'
#!/bin/sh
echo "xrandr $*" >> "${CALLS}"
case "$*" in
    *--rotate*) for a; do last="$a"; done; echo "${last}" > "${ROT}" ;;
    *) echo "Screen 0: minimum 8 x 8, current 1280 x 720, maximum 16384 x 16384"
       echo "DSI-0 connected primary 1280x720+0+0 (0x1c4) $(cat "${ROT}") (normal left inverted right x axis y axis) 0mm x 0mm"
       echo "HDMI-0 disconnected (normal left inverted right x axis y axis)" ;;
esac
EOF
# xinput: a touchscreen whose name has spaces, and a pad that is not one
cat > "${tmp}/bin/xinput" << 'EOF'
#!/bin/sh
case "$1" in
    list) printf '%s\n' "Virtual core pointer" "st_stmfts touchscreen" "Nintendo Switch Lite Gamepad" ;;
    set-prop) shift; printf 'xinput set-prop' >> "${CALLS}"; printf ' [%s]' "$@" >> "${CALLS}"; echo >> "${CALLS}" ;;
esac
EOF
chmod +x "${tmp}/bin/"*
export PATH="${tmp}/bin:${PATH}"
ROTATE="${BIN}/switch-rotate"

check "--show says the current rotation" test "$("${ROTATE}" --show)" = normal
"${ROTATE}" next
check "next turns it to portrait (left)" test "$(cat "${ROT}")" = left
check "on the Switch's screen" grep -q 'xrandr --output DSI-0 --rotate left' "${CALLS}"
check "the touchscreen gets the portrait matrix, its name whole" \
    grep -qF 'xinput set-prop [st_stmfts touchscreen] [--type=float] [Coordinate Transformation Matrix] [0] [-1] [1] [1] [0] [0] [0] [0] [1]' "${CALLS}"
check_not "the pad is left alone" grep -q 'Gamepad' "${CALLS}"
check "the choice is saved" test "$(cat "${XDG_CONFIG_HOME}/nxd/rotation")" = left
"${ROTATE}" next
"${ROTATE}" next
"${ROTATE}" next
check "four times next comes back to landscape" test "$(cat "${ROT}")" = normal
"${ROTATE}" inverted_portrait
check "the README's names work (inverted_portrait = right)" test "$(cat "${ROT}")" = right
echo normal > "${ROT}"
"${ROTATE}" --restore
check "--restore puts back the saved one" test "$(cat "${ROT}")" = right
rm -f "${XDG_CONFIG_HOME}/nxd/rotation"
: > "${CALLS}"
"${ROTATE}" --restore
check "--restore with nothing saved does nothing" test ! -s "${CALLS}"
check_not "an unknown rotation is refused" "${ROTATE}" sideways
check "--help works" "${ROTATE}" --help

check "switch-sensors prints one line with --plain" grep -qE '^.*°C \| Fan: .+$' <<< "$("${BIN}/switch-sensors" --plain)"
check "switch-sensors writes genmon's tags for the panel" grep -q '^<txt>' <<< "$("${BIN}/switch-sensors" < /dev/null | cat)"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
