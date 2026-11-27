#!/usr/bin/env bash
# shellcheck disable=SC2016
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

# Nothing here may wait for a person at a terminal.
exec < /dev/null

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
check "retrobox logs into retrobox-system-settings' Openbox session" test "$(variant_setting retrobox NXD_AUTOLOGIN_SESSION)" = "retrobox-openbox"
RPKG="${NXD_ROOT}/packages/nxd-retrobox"
RLIST="${RPKG}/root/usr/share/nxd/releases.d/retrobox.list"
check "that session comes from retrobox-system-settings' releases" \
    grep -qx 'RetroboxProject/retrobox-system-settings retrobox-system-settings retrobox-session-openbox' "${RLIST}"
check_not "nxd-retrobox has no session of its own any more" test -e "${RPKG}/root/usr/lib/nxd/retrobox-session"
HOOK="${RPKG}/root/etc/retrobox/session.d/50-nxd-emulationstation"
check "the session's step puts EmulationStation's defaults in place" test -x "${HOOK}"
# shellcheck disable=SC2016 # the literal text of the script
check "...only if missing" grep -q '\[ -e "${frontend}/${file}" \] || cp' "${HOOK}"
# shellcheck disable=SC2016 # the literal text of the script
check "the console's user gets the polkit rule" grep -q 'retrobox-polkit-rule "${user}" > /etc/polkit-1/rules.d/50-retrobox-console.rules' \
    "${NXD_ROOT}/config/hooks/retrobox/30-retrobox-polkit.sh"
check "nxd-retrobox needs what its files run" grep -q '^Depends: nxd-common (= @VERSION@), openbox, picom, pulseaudio-utils, dosfstools' "${RPKG}/DEBIAN/control.in"
check "the retrobox overlay is gone: its files are in nxd-retrobox" test ! -e "${NXD_ROOT}/config/overlay/retrobox"
# shellcheck disable=SC2016 # the literal text of the script
check "the firmware names are made by nxd-common" grep -q 'brcmfmac4356-pcie.nintendo,${model}.txt' "${NXD_ROOT}/packages/nxd-common/DEBIAN/postinst"
check "and again when a package changes the firmware" grep -qx 'interest-noawait /usr/lib/firmware/brcm' "${NXD_ROOT}/packages/nxd-common/DEBIAN/triggers"
check "xfce logs into XFCE" test "$(variant_setting xfce NXD_AUTOLOGIN_SESSION)" = "xfce"
check "retrobox has a default user" test "$(variant_setting retrobox NXD_DEFAULT_USER)" = "retrobox"
check "retrobox has a default password" test "$(variant_setting retrobox NXD_DEFAULT_PASSWORD)" = "retrobox"
check "retrobox installs the retrobox releases" test "$(variant_setting retrobox NXD_RELEASE_LIST)" = "retrobox"
check "retrobox-update reads the console's release list" test "$(readlink "${RPKG}/root/etc/retrobox/releases.d/retrobox.list")" = /usr/share/nxd/releases.d/retrobox.list
check_not "retrobox-update knows nothing of nxd-update" grep -q 'system_updater' "${RPKG}/root/etc/retrobox/retrobox.ini.d/50-nxd.ini"
# shellcheck disable=SC2016 # the literal text of the script
check "nxd-update runs retrobox-update whole on the Retrobox image" \
    grep -q 'RETROBOX_UPDATE_INHIBITED=1 "${RETROBOX_UPDATE}" "${flags\[@\]}"' "${NXD_ROOT}/packages/nxd-common/root/usr/bin/nxd-update"
check "the overlay may run nxd-update as root" \
    grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/bin/nxd-update</annotate>' "${NXD_ROOT}/packages/nxd-common/root/usr/share/polkit-1/actions/org.nxd.update.policy"
check "the retrobox release list names the five components" test "$(grep -c '^RetroboxProject/' "${NXD_ROOT}/packages/nxd-retrobox/root/usr/share/nxd/releases.d/retrobox.list")" -eq 5
check "retrobox has a compositor" has_line "${RETROBOX}" picom
check_not "picom's backend is the session's default (glx)" grep -q '^\[openbox\]' "${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/retrobox.ini.d/50-nxd.ini"
check "retrobox leaves ssh on" test -z "$(variant_setting retrobox NXD_DISABLE_UNITS)"
check "xfce has a default user" test "$(variant_setting xfce NXD_DEFAULT_USER)" = "switch"
check "xfce keeps ssh off" grep -q 'ssh.service' <(variant_setting xfce NXD_DISABLE_UNITS)
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
    grep -Eq '^Package: libpcre3( |$)' <(render_compat_pins)
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
check "dry run adds Moonlight's repository, with its key and pins" \
    bash -c "grep -q 'nxd-moonlight-l4t.sources' <<< \"\$1\" && grep -q 'moonlight-l4t.asc' <<< \"\$1\" && grep -q '20-nxd-moonlight-l4t.pref' <<< \"\$1\"" _ "${DRY}"
ML_SOURCES="$(repo_sources_file moonlight-l4t arm64)"
ML_PINS="$(repo_pins moonlight-l4t)"
check "Moonlight's source is the noble one" grep -qx 'Suites: noble' <<< "${ML_SOURCES}"
check "...signed by its key" grep -qx 'Signed-By: /etc/apt/keyrings/moonlight-l4t.asc' <<< "${ML_SOURCES}"
check "...and it only gives what Debian has not" grep -qx 'Pin: origin "dl.cloudsmith.io"' <<< "${ML_PINS}"
check "...at priority 100" grep -qx 'Pin-Priority: 100' <<< "${ML_PINS}"
check "Moonlight's key is in git and is the expected one" \
    bash -c ". '${NXD_ROOT}/scripts/lib/common.sh'; verify_repo_key moonlight-l4t"
check_not "an unknown repository is refused" \
    bash -c ". '${NXD_ROOT}/scripts/lib/common.sh'; repo_setting nope REPO_URL"
for variant in retrobox xfce; do
    check "${variant} has Moonlight and the Megascript's tools" \
        bash -c "grep -qx moonlight-qt <<< \"\$1\" && grep -qx yad <<< \"\$1\" && grep -qx software-properties-common <<< \"\$1\"" _ "$(variant_packages "${variant}")"
    check "${variant} adds Moonlight's repository" test "$(variant_setting "${variant}" NXD_APT_REPOS)" = moonlight-l4t
done
check "software-properties-common comes from the compat suite" \
    grep -q -A1 '^Package: .*software-properties-common' <(render_compat_pins)

check "retrobox does not ship docs or kernel headers" grep -q 'dpkg.cfg.d' <<< "${DRY}"
check "dpkg excludes list the headers" grep -q 'path-exclude=/usr/src/linux-headers-\*' <(dpkg_excludes_file retrobox)
check "retrobox masks the apt timers" grep -q 'apt-daily.timer' <(variant_setting retrobox NXD_MASK_UNITS)
check "retrobox keeps NetworkManager" test -z "$(variant_setting retrobox NXD_MASK_UNITS | grep -i 'networkmanager\|bluetooth\|pulse' || true)"
check "dpkg excludes are not expanded as globs" test "$(dpkg_excludes_file retrobox | wc -l)" -le 8
check "dpkg excludes keep the copyright files" grep -q 'path-include=/usr/share/doc/\*/copyright' <(dpkg_excludes_file retrobox)
check "xfce has no dpkg excludes" test -z "$(dpkg_excludes_file xfce)"
check "a user is staged by --user" grep -q 'nxd-user' <("${NXD}" rootfs --variant xfce --user manu --no-password --dry-run --output "${tmp}/out")
check_not "a bad login name is refused" "${NXD}" rootfs --variant xfce --user 'Bad Name' --no-password --dry-run --output "${tmp}/out"
check_not "--no-password needs a user" "${NXD}" rootfs --variant xfce --no-user --no-password --dry-run --output "${tmp}/out"
check "retrobox dry run needs no prompt for its user" "${NXD}" rootfs --variant retrobox --dry-run --output "${tmp}/out" < /dev/null
check_not "an empty --releases-dir is refused" "${NXD}" rootfs --variant retrobox --dry-run --releases-dir "${tmp}" --output "${tmp}/out"
check "retrobox has no gamepad-as-mouse packages" test -z "$(grep -E 'joystick' <<< "${RETROBOX}" || true)"
check "xfce has the gamepad-as-mouse packages" has_line "${XFCE}" "switch-joystick-mouse"
check "xfce has the joystick driver" has_line "${XFCE}" "xserver-xorg-input-joystick"
check "retrobox drops the joystick Xorg config whatever package brings it" \
    grep -q 'path-exclude=/usr/share/X11/xorg.conf.d/\*joystick\*.conf' <(dpkg_excludes_file retrobox)
check "retrobox preloads the theme, the bezels and the shaders" \
    test "$(variant_setting retrobox NXD_PRELOAD)" = "theme bezels shaders"
check "retrobox runs in console mode" grep -qx 'console_mode = true' \
    "${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/retrobox.ini.d/50-nxd.ini"
# shellcheck disable=SC2016
check "console_mode is in the [core] section" \
    awk '/^\[/{section=$0} /^console_mode = true/{found=(section=="[core]")} END{exit !found}' \
    "${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/retrobox.ini.d/50-nxd.ini"
check "retrobox confirms with the east button, as Nintendo pads do" grep -q 'name="InvertButtons" value="true"' \
    "${NXD_ROOT}/packages/nxd-retrobox/root/usr/share/nxd/retrobox/emulationstation/es_settings.cfg"
ESIN="${NXD_ROOT}/packages/nxd-retrobox/root/usr/share/nxd/retrobox/emulationstation/es_input.cfg"
check "retrobox ships a configured keyboard, so ES never asks for one" grep -q 'deviceName="Keyboard" deviceGUID="-1"' "${ESIN}"
check "retrobox ships the Switch Lite pad with Home as the hotkey" \
    grep -q 'deviceGUID="06004c277e05000023f1000000000000"' "${ESIN}"
check "the pad has its hotkey" grep -q 'name="hotkey" type="button" id="11"' "${ESIN}"
check_not "Openbox's rc.xml (volume and power keys) is the session's" \
    test -e "${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/openbox/rc.xml"
check "the power button suspends the console" grep -qx 'HandlePowerKey=suspend' \
    "${NXD_ROOT}/packages/nxd-retrobox/root/etc/systemd/logind.conf.d/10-nxd-power.conf"
PMHOOK="${NXD_ROOT}/packages/nxd-retrobox/root/usr/lib/systemd/system-sleep/nxd-picom"
check "the hook that closes the compositor across a suspend is executable" test -x "${PMHOOK}"
check "the hook records the user, environment and invocation before the suspend" grep -q 'nxd-picom.env' "${PMHOOK}"
check "the hook kills picom outright before the suspend (SIGTERM took half a second)" grep -q 'kill -KILL "${pid}"' "${PMHOOK}"
check "the hook reopens picom at the resume, as the user that ran it" grep -q 'runuser -u "${user}" -- env -i' "${PMHOOK}"
check "the hook reopens picom with its environment and invocation" grep -q 'sh -c "${cmd}"' "${PMHOOK}"
check "the hook leaves a session without picom alone" grep -qF 'pid="$(picom_pid)" || exit 0' "${PMHOOK}"
check "the hook leaves a resumed picom alone" grep -qF 'if [ -n "$(picom_pid)" ]; then' "${PMHOOK}"

# end-to-end, with a fake picom (a script that waits, and the kernel
# calls it "picom") and a systemd-run stub: the pre hook records the user,
# the environment and the invocation and kills it; the post hook reopens it
# in a unit of its own, as the recorded user, with the recorded environment
# and invocation, without -b (the unit lives as long as picom).
check "the sleep hook closes the compositor and reopens it at the resume" bash -c '
    PMHOOK="$1"
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/bin" "${tmp}/state"
    # a script: the kernel names its process after it, and it takes -b
    printf "#!/bin/sh\nwhile :; do sleep 1; done\n" > "${tmp}/bin/picom"
    chmod +x "${tmp}/bin/picom"
    printf "#!/bin/sh\necho \"\$*\" >\""${tmp}"/run.log\"\n" > "${tmp}/bin/systemd-run"
    printf "#!/bin/sh\nexit 0\n" > "${tmp}/bin/systemctl"
    chmod +x "${tmp}/bin/systemd-run" "${tmp}/bin/systemctl"
    PATH="${tmp}/bin:${PATH}" NXD_PICOM_STATE_DIR="${tmp}/state" bash -c "
        env -i PATH=/usr/bin:/bin DISPLAY=:0 XAUTHORITY=x HOME=/home/user ${tmp}/bin/picom 600 -b &
        pid=\$!
        for _ in \$(seq 1 40); do grep -qx picom /proc/\${pid}/comm 2> /dev/null && break; sleep 0.25; done
        ${PMHOOK} pre
        ! grep -q ^State:.*[RS] /proc/\${pid}/status 2> /dev/null &&
        grep -qx $(id -u) ${tmp}/state/nxd-picom.user &&
        grep -q DISPLAY=:0 ${tmp}/state/nxd-picom.env &&
        grep -q . ${tmp}/state/nxd-picom.cmd &&
        ${PMHOOK} post &&
        grep -q -- --unit=nxd-picom-resume ${tmp}/run.log && grep -q DISPLAY=:0 ${tmp}/run.log &&
        grep -q -- --uid=$(id -u)[[:space:]] ${tmp}/run.log &&
        grep -q picom.600\$ ${tmp}/run.log &&
        ! ls ${tmp}/state/nxd-picom.* > /dev/null 2>&1
    "
' _ "${PMHOOK}"
ESSET="${NXD_ROOT}/packages/nxd-retrobox/root/usr/share/nxd/retrobox/emulationstation/es_settings.cfg"
check "the theme's text is 125 %, for a small screen" grep -q 'name="FontScale" value="1.25"' "${ESSET}"
check "the menus' text is 125 %" grep -q 'name="MenuFontScale" value="1.25"' "${ESSET}"
RBINI="${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/retrobox.ini.d/50-nxd.ini"
for folder in roms saves bios; do
    check "the ${folder} are in the SD card" grep -qx "${folder}_dir = /sdcard/retrobox/${folder}" "${RBINI}"
done
check "they are in [paths]" bash -c "awk '/^\\[/{s=\$0} /^roms_dir = /{f=(s==\"[paths]\")} END{exit !f}' '${RBINI}'"
check "the rest stays where Retrobox puts it" test -z "$(grep -E '^(data_dir|state_dir) *=' "${RBINI}" || true)"
check "nothing sets or reads RETROBOX_CONFIGDIR any more" test -z "$(grep -rl 'RETROBOX_CONFIGDIR' "${NXD_ROOT}/config" "${NXD_ROOT}/packages" || true)"
check "Retrobox's configuration is in /etc/retrobox only" test ! -e "${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox-system-settings"
check "the card's tools are installed" has_line "${RETROBOX}" "dosfstools"
check "the retrobox data hook is executable" test -x "${NXD_ROOT}/config/hooks/retrobox/10-retrobox-data.sh"
check "lightdm starts X without asking logind" \
    grep -qx 'logind-check-graphical=false' "${NXD_ROOT}/packages/nxd-common/root/etc/lightdm/lightdm.conf.d/10-nxd-seat.conf"
# shellcheck disable=SC2016
check "that option is in the [LightDM] section" \
    awk '/^\[/{section=$0} /^logind-check-graphical=false/{found=(section=="[LightDM]")} END{exit !found}' \
    "${NXD_ROOT}/packages/nxd-common/root/etc/lightdm/lightdm.conf.d/10-nxd-seat.conf"
check "the console has killall and chvt" bash -c "grep -qx psmisc '${NXD_ROOT}/config/packages/base.list' && grep -qx kbd '${NXD_ROOT}/config/packages/base.list'"
"${NXD}" rootfs --variant retrobox --dry-run --output "${tmp}/out1" > /dev/null 2>&1 || true
check "the preload list is staged for retrobox" grep -qx shaders "${tmp}/out1/retrobox/stage/nxd-preload"
"${NXD}" rootfs --variant retrobox --no-preload --dry-run --output "${tmp}/out2" > /dev/null 2>&1 || true
check "--no-preload stages nothing" test ! -s "${tmp}/out2/retrobox/stage/nxd-preload"
check "xfce has nothing to preload" test -z "$(variant_setting xfce NXD_PRELOAD)"
check "retrobox installs RetroArch in the image" test "$(variant_setting retrobox NXD_EMULATORS)" = "retroarch"
check "xfce installs no emulators" test -z "$(variant_setting xfce NXD_EMULATORS)"
check "the emulators hook is executable" test -x "${NXD_ROOT}/config/hooks/retrobox/20-retrobox-emulators.sh"
check "the emulator list is staged for retrobox" grep -qx retroarch "${tmp}/out1/retrobox/stage/nxd-emulators"
check "--no-preload stages no emulators" test ! -s "${tmp}/out2/retrobox/stage/nxd-emulators"
check "the emulator list is copied into the image" grep -q 'nxd-emulators' <("${NXD}" rootfs --variant retrobox --dry-run --output "${tmp}/out3" 2>&1)
for lib in libasound2t64 libpulse0 libgl1 libegl1 libsdl2-2.0-0 libxkbcommon0 libgbm1; do
    check "retrobox has ${lib} for the RetroArch binary" has_line "${RETROBOX}" "${lib}"
done
check "--no-releases is accepted" "${NXD}" rootfs --variant retrobox --no-releases --dry-run --output "${tmp}/out" < /dev/null
check "--no-user is accepted" "${NXD}" rootfs --variant retrobox --no-user --no-releases --dry-run --output "${tmp}/out" < /dev/null
check "--user takes the password from NXD_PASSWORD" env NXD_PASSWORD=x "${NXD}" rootfs --variant xfce --user manu --dry-run --output "${tmp}/out"
check_not "unknown variant is refused" "${NXD}" rootfs --variant nope --dry-run --output "${tmp}/out"
check "--prereleases is accepted by rootfs" "${NXD}" rootfs --variant retrobox --prereleases --dry-run --output "${tmp}/out" < /dev/null
check "rootfs documents --prereleases" grep -q -- '--prereleases' <("${NXD}" rootfs --help)
check "build documents --prereleases" grep -q -- '--prereleases' <("${NXD}" build --help)
check "the container forwards NXD_PRERELEASES" grep -q 'NXD_PRERELEASES' "${NXD_ROOT}/scripts/in-container.sh"
check "the workflow has a prereleases input" grep -q 'prereleases:' "${NXD_ROOT}/.github/workflows/build.yml"
check "build has a help text" grep -q "Usage: sudo nxd build" <("${NXD}" build --help)
check_not "unknown command is refused" "${NXD}" frobnicate


# The desktop build asks for the user and the password at a terminal. The dry
# run writes the answer into the stage, which is what is read back here.
ask() {
    python3 -I - "$@" << 'PY'
import os, pty, sys, time
nxd, out, answers = sys.argv[1], sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.execv(nxd, [nxd, "rootfs", "--variant", "xfce", "--dry-run", "--output", out])
for answer in answers:
    time.sleep(1.0)
    os.write(fd, answer.encode() + b"\n")
try:
    while os.read(fd, 4096):
        pass
except OSError:
    pass
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
PY
}
check "at a terminal the desktop build asks for the user name" bash -c "$(declare -f ask); ask '${NXD}' '${tmp}/ask1' bob pw pw && [[ \"\$(sed -n 1p '${tmp}/ask1/xfce/stage/nxd-user')\" == bob ]]"
check "Enter keeps the default user" bash -c "$(declare -f ask); ask '${NXD}' '${tmp}/ask2' '' '' && [[ \"\$(sed -n 1p '${tmp}/ask2/xfce/stage/nxd-user')\" == switch ]]"
check_not "different passwords are refused" bash -c "$(declare -f ask); ask '${NXD}' '${tmp}/ask3' bob one two"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
