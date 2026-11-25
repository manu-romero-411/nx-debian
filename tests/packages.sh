#!/usr/bin/env bash
# Test of nx-debian's own packages: what build-packages.sh (nxd debs) puts in
# them, and which packages nxd-update takes from GitHub releases, against a
# fake GitHub API served over http on localhost (--download-only: no apt).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
UPDATE="${NXD_ROOT}/packages/nxd-common/root/usr/bin/nxd-update"

for tool in curl jq dpkg-deb python3 git; do
    command -v "${tool}" > /dev/null 2>&1 || { echo "skipped: no ${tool}"; exit 0; }
done

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
server=""
cleanup() {
    [[ -z "${server}" ]] || kill "${server}" 2> /dev/null || true
    rm -rf "${tmp}"
}
trap cleanup EXIT

## build-packages.sh ---------------------------------------------------------

"${NXD_ROOT}/scripts/build-packages.sh" --version 1.2.3 "${tmp}/debs" > /dev/null 2>&1
COMMON="${tmp}/debs/nxd-common_1.2.3_all.deb"
RETRO="${tmp}/debs/nxd-retrobox_1.2.3_all.deb"
check "nxd-common is built" test -f "${COMMON}"
check "nxd-retrobox is built" test -f "${RETRO}"
check "the version is the one asked for" test "$(dpkg-deb -f "${COMMON}" Version)" = 1.2.3
check "nxd-retrobox needs the nxd-common of its version" \
    grep -q 'nxd-common (= 1.2.3)' <<< "$(dpkg-deb -f "${RETRO}" Depends)"
check "the files under /etc are conffiles" \
    grep -qx '/etc/retrobox/retrobox.ini.d/50-nxd.ini' <<< "$(dpkg-deb --ctrl-tarfile "${RETRO}" | tar -xO ./conffiles)"
check "the files belong to root" test -z "$(dpkg-deb -c "${RETRO}" | awk '$2 != "root/root"')"
check "nxd-update is executable" grep -q '^-rwxr-xr-x .*\./usr/bin/nxd-update$' <<< "$(dpkg-deb -c "${COMMON}")"
# Debian's PATH for a user (/etc/profile, /etc/login.defs) has no sbin: in
# /usr/sbin, `nxd-update` was "command not found" for the console's user
check_not "...and in a user's PATH, not in /usr/sbin" grep -q '\./usr/sbin/' <<< "$(dpkg-deb -c "${COMMON}")"
check "the session's step is executable" grep -q '^-rwxr-xr-x .*\./etc/retrobox/session.d/50-nxd-emulationstation$' <<< "$(dpkg-deb -c "${RETRO}")"
check "the compositor sleep hook is in nxd-retrobox, executable" grep -q '^-rwxr-xr-x .*\./usr/lib/systemd/system-sleep/nxd-picom$' <<< "$(dpkg-deb -c "${RETRO}")"
check "the Capture button's step is executable" grep -q '^-rwxr-xr-x .*\./etc/retrobox/session.d/60-nxd-capture-button$' <<< "$(dpkg-deb -c "${RETRO}")"
check "the Capture button's program is executable" grep -q '^-rwxr-xr-x .*\./usr/share/nxd/retrobox/capture-button$' <<< "$(dpkg-deb -c "${RETRO}")"
check "the triggers are in nxd-common" grep -qx './triggers' <<< "$(dpkg-deb --ctrl-tarfile "${COMMON}" | tar -t)"
check "--variant xfce builds nxd-common and nxd-xfce" bash -c \
    "'${NXD_ROOT}/scripts/build-packages.sh' --version 1 --variant xfce '${tmp}/xfce' && test \"\$(ls '${tmp}/xfce' | tr '\n' ' ')\" = 'nxd-common_1_all.deb nxd-xfce_1_all.deb '"
XFCE="${tmp}/debs/nxd-xfce_1.2.3_all.deb"
check "nxd-xfce is built" test -f "${XFCE}"
check "nxd-xfce needs the nxd-common of its version" grep -q 'nxd-common (= 1.2.3)' <<< "$(dpkg-deb -f "${XFCE}" Depends)"
check "switch-rotate is in nxd-xfce, executable" grep -q '^-rwxr-xr-x .*\./usr/bin/switch-rotate$' <<< "$(dpkg-deb -c "${XFCE}")"
check "the desktop's defaults are conffiles" \
    grep -qx '/etc/xdg/nxd/xfce4/panel/default.xml' <<< "$(dpkg-deb --ctrl-tarfile "${XFCE}" | tar -xO ./conffiles)"
check_not "nxd-xfce owns no file of the XFCE packages" grep -qE '\./etc/xdg/xfce4/' <<< "$(dpkg-deb -c "${XFCE}")"
check_not "switch-rotate is not in the console" grep -q 'switch-rotate' <<< "$(dpkg-deb -c "${RETRO}")"
check "--variant retrobox builds both" bash -c \
    "'${NXD_ROOT}/scripts/build-packages.sh' --version 1 --variant retrobox '${tmp}/rb' && test \"\$(ls '${tmp}/rb' | wc -l)\" -eq 2"
check_not "a version that is not one is refused" "${NXD_ROOT}/scripts/build-packages.sh" --version v1 "${tmp}/bad"

## the performance backend (nxd-common) and indicator (nxd-xfce)

CPKG="${NXD_ROOT}/packages/nxd-common"
HELPER="${CPKG}/root/usr/lib/nxd/nvpmodel-helper"
POLICY="${CPKG}/root/usr/share/polkit-1/actions/org.nxd.nvpmodel.policy"
check "the helper is in nxd-common" grep -q '\./usr/lib/nxd/nvpmodel-helper$' <<< "$(dpkg-deb -c "${COMMON}")"
check "the policy is in nxd-common" grep -q 'org.nxd.nvpmodel.policy$' <<< "$(dpkg-deb -c "${COMMON}")"
check "the user at the console needs no password" test "$(grep -c '<allow_active>yes</allow_active>' "${POLICY}")" -eq 2
check "anyone else needs an administrator's" test "$(grep -c '<allow_any>auth_admin</allow_any>' "${POLICY}")" -eq 2
check "the policy covers nvpmodel (the overlay runs it)" grep -q '>/usr/sbin/nvpmodel<' "${POLICY}"
check "...and the helper" grep -q '>/usr/lib/nxd/nvpmodel-helper<' "${POLICY}"
check "nxd-common needs pkexec" grep -q 'pkexec' <<< "$(dpkg-deb -f "${COMMON}" Depends)"
check "the saved settings are applied at boot" grep -qx 'ExecStart=/usr/lib/nxd/nvpmodel-helper restore' \
    "${CPKG}/root/usr/lib/systemd/system/nxd-nvpmodel-restore.service"
check "...by a unit nxd-common enables" grep -q 'for unit in nxd-nvpmodel-restore.service' "${CPKG}/DEBIAN/postinst"
check_not "the helper refuses what is not a number" "${HELPER}" 10 '1; rm -rf /'
check "...with its usage status" bash -c "'${HELPER}' 7 abc; test \$? -eq 2"
check_not "the helper needs an action" "${HELPER}"
check_not "no file is opened to everyone" grep -q 'chmod 666' "${HELPER}"
IND="${NXD_ROOT}/packages/nxd-xfce/root/usr/share/nxd/nvpmodel-indicator/nvpmodel_indicator.py"
check "the indicator compiles" python3 -m py_compile "${IND}"
check "the indicator uses nxd-common's helper" grep -q '^nvpmodel_helper_path = "/usr/lib/nxd/nvpmodel-helper"$' "${IND}"
check "...for switch-bsp's nvpmodel module too" grep -q '^nvpm.nvpmodel_helper_path = nvpmodel_helper_path$' "${IND}"
check_not "...and never writes as the user through it" grep -qE "subprocess.call\(\[nvpmodel_helper_path, (SET_|'7'|'10')" "${IND}"
check "NVIDIA's and CTCaer's copyrights are kept" grep -q 'Copyright (c) 2021, CTCaer' "${IND}"
check "the indicator starts in XFCE only" grep -qx 'OnlyShowIn=XFCE;' "${NXD_ROOT}/packages/nxd-xfce/root/etc/xdg/autostart/nxd-nvpmodel-indicator.desktop"
check "nxd-xfce brings Ayatana for it" grep -q 'gir1.2-ayatanaappindicator3-0.1' <<< "$(dpkg-deb -f "${XFCE}" Depends)"

## the console's text, the volume toast

OVINI="${NXD_ROOT}/packages/nxd-retrobox/root/etc/retrobox/overlay.ini"
check "the overlay shows the volume toast" bash -c "awk '/^\\[/{s=\$0} /^toast = true\$/{f=(s==\"[volume]\")} END{exit !f}' '${OVINI}'"
check "...from a conffile of nxd-retrobox" \
    grep -qx '/etc/retrobox/overlay.ini' <<< "$(dpkg-deb --ctrl-tarfile "${RETRO}" | tar -xO ./conffiles)"
check_not "the volume buttons are retrobox-session-openbox's (retrobox-volume)" test -e "${NXD_ROOT}/packages/nxd-retrobox/root/usr/bin/nxd-volume"
check "nxd-common sets Terminus 8x16 for the consoles" \
    grep -q "s/^FONTFACE=.*/FONTFACE=\"Terminus\"/' -e 's/^FONTSIZE=.*/FONTSIZE=\"8x16\"/" "${CPKG}/DEBIAN/postinst"
# shellcheck disable=SC2016 # the literal text of the script
check "...only on a first install" grep -q '\[ -n "${2:-}" \] || console_font' "${CPKG}/DEBIAN/postinst"
check "...and in debconf, so that console-setup keeps it" grep -q 'console-setup/fontface47 select Terminus' "${CPKG}/DEBIAN/postinst"
check "nxd-common needs console-setup" grep -q 'console-setup' <<< "$(dpkg-deb -f "${COMMON}" Depends)"
check "fastfetch is in every image" grep -qx 'fastfetch' "${NXD_ROOT}/config/packages/base.list"

## the root filesystem: grown to its partition on the first boot

GROWFS="${CPKG}/root/usr/lib/nxd/growfs"
if command -v mkfs.ext4 > /dev/null 2>&1 && command -v resize2fs > /dev/null 2>&1; then
    truncate -s 64M "${tmp}/rootfs.ext4"
    mkfs.ext4 -q -F "${tmp}/rootfs.ext4"
    truncate -s 256M "${tmp}/rootfs.ext4"
    sh "${GROWFS}" "${tmp}/rootfs.ext4" > "${tmp}/growfs.log" 2>&1
    check "a small filesystem fills its partition" \
        test "$(dumpe2fs -h "${tmp}/rootfs.ext4" 2> /dev/null | sed -n 's/^Block count: *//p')" -eq 65536
    check "...saying so" grep -q 'nxd-growfs: .*: 64 MiB of 256 MiB: growing it' "${tmp}/growfs.log"
    check_not "...and once it does, nothing more" test -n "$(sh "${GROWFS}" "${tmp}/rootfs.ext4" 2>&1)"
    rm -f "${tmp}/rootfs.ext4"
fi
check "it runs on every boot" grep -qx 'WantedBy=multi-user.target' "${CPKG}/root/usr/lib/systemd/system/nxd-growfs.service"
check "...enabled by nxd-common" grep -q 'for unit in nxd-nvpmodel-restore.service nxd-growfs.service' "${CPKG}/DEBIAN/postinst"
check "...which needs resize2fs" grep -qw 'e2fsprogs' <<< "$(dpkg-deb -f "${COMMON}" Depends)"
for tool in parted fdisk gdisk e2fsprogs dosfstools exfatprogs mtools ntfs-3g btrfs-progs xfsprogs f2fs-tools jfsutils udftools gpart dmsetup kpartx; do
    check "${tool} is in every image" grep -qx "${tool}" "${NXD_ROOT}/config/packages/base.list"
done

## the locales: the common ones of Europe, generated

LOCS="${CPKG}/root/usr/share/nxd/locales"
ENSURE="${CPKG}/root/usr/lib/nxd/ensure-locales"
for loc in es_ES en_US en_GB fr_FR de_DE it_IT pl_PL ru_RU uk_UA el_GR ca_ES eu_ES gl_ES; do
    check "${loc} is generated in every image" grep -qx "${loc}.UTF-8 UTF-8" "${LOCS}"
done
check "nxd-common ships the list and the helper" \
    bash -c "dpkg-deb -c '${COMMON}' | grep -q './usr/share/nxd/locales\$' && dpkg-deb -c '${COMMON}' | grep -q '^-rwxr-xr-x.*./usr/lib/nxd/ensure-locales\$'"
check "...needs locales" grep -qw 'locales' <<< "$(dpkg-deb -f "${COMMON}" Depends)"
check "...which every image installs" grep -qx 'locales' "${NXD_ROOT}/config/packages/base.list"
check "...and runs the helper on every configure" grep -q '/usr/lib/nxd/ensure-locales ||' "${CPKG}/DEBIAN/postinst"
# Debian's /etc/locale.gen: everything commented out
printf '%s\n' "# This file lists locales that you wish to have built." "#" "# en_US.UTF-8 UTF-8" \
    "# es_ES ISO-8859-1" "#  es_ES.UTF-8 UTF-8" "nl_NL.UTF-8 UTF-8" > "${tmp}/locale.gen"
sh "${ENSURE}" --no-generate "${LOCS}" "${tmp}/locale.gen"
check "a commented locale is uncommented" grep -qx 'es_ES.UTF-8 UTF-8' "${tmp}/locale.gen"
check "...once" test "$(grep -c 'es_ES.UTF-8' "${tmp}/locale.gen")" -eq 1
check "one not in the file is added" grep -qx 'uk_UA.UTF-8 UTF-8' "${tmp}/locale.gen"
check "the administrator's locales stay" grep -qx 'nl_NL.UTF-8 UTF-8' "${tmp}/locale.gen"
check "...and the other charsets stay commented" grep -qx '# es_ES ISO-8859-1' "${tmp}/locale.gen"
check "all of them are there" test "$(grep -c '^[a-z][a-z]_[A-Z][A-Z].UTF-8 UTF-8$' "${tmp}/locale.gen")" -eq 14
cp "${tmp}/locale.gen" "${tmp}/locale.gen.before"
sh "${ENSURE}" --no-generate "${LOCS}" "${tmp}/locale.gen"
check "a second run changes nothing" cmp -s "${tmp}/locale.gen" "${tmp}/locale.gen.before"

## the volume: Switchroot's UCM profile put the speaker and the headphones at
## 100% on every start of PulseAudio

UCMV="${CPKG}/root/usr/lib/nxd/ucm-volume"
UCMF=/usr/share/alsa/ucm2/Tegra/tegra-snd-t210ref-mobile-rt565x/HiFi.conf
cat > "${tmp}/HiFi.orig" << 'UCM'
SectionDevice."Headphones" {
	EnableSequence [
		cset "name='x HP L Playback Switch' on"
		cset "name='x DAC1 HP Playback Volume' 170,170"
		cset "name='x HP Playback Volume' 31,31"
	]
	DisableSequence [
		cset "name='x HP Playback Volume' 0,0"
		cset "name='x DAC1 HP Playback Volume' 0,0"
	]
	Value {
		PlaybackVolume "x DAC1 HP Playback Volume"
	}
}
SectionDevice."Speaker" {
	EnableSequence [
		cset "name='x DAC1 Speaker Playback Volume' 148,148"
		cset "name='x Speaker Playback Volume' 35,35"
	]
	DisableSequence [
		cset "name='x DAC1 Speaker Playback Volume' 0,0"
	]
	Value {
		PlaybackVolume "x DAC1 Speaker Playback Volume"
	}
}
UCM
sh "${UCMV}" "${tmp}/HiFi.orig" "${tmp}/HiFi.conf"
check_not "the DAC1 volumes are not set by the profile" grep -q "cset \"name='x DAC1" "${tmp}/HiFi.conf"
check "...which still tells PulseAudio which control is the volume" test "$(grep -c 'PlaybackVolume "x DAC1' "${tmp}/HiFi.conf")" -eq 2
check "...and keeps the rest of the sequences" \
    test "$(grep -c 'cset' "${tmp}/HiFi.conf")" -eq "$(($(grep -c 'cset' "${tmp}/HiFi.orig") - 4))"
check "...saying where it comes from" grep -q '^# Made by nxd-common' "${tmp}/HiFi.conf"
rm -f "${tmp}/HiFi.conf"
sh "${UCMV}" "${tmp}/none" "${tmp}/HiFi.conf"
check_not "without Switchroot's profile, nothing is made" test -e "${tmp}/HiFi.conf"
# shellcheck disable=SC2016 # the literal text of the script
check "Switchroot's profile is diverted before it is unpacked" \
    grep -q -- '--divert "${ucm}.switch-alsa-ucm2" --add "${ucm}"' "${CPKG}/DEBIAN/preinst"
check "...made again when switch-alsa-ucm2 changes it" \
    grep -qx "interest-noawait ${UCMF%/*}" <<< "$(dpkg-deb --ctrl-tarfile "${COMMON}" | tar -xO ./triggers)"
# shellcheck disable=SC2016 # the literal text of the script
check "...and given back on remove" grep -q -- '--divert "${ucm}.switch-alsa-ucm2" --remove "${ucm}"' "${CPKG}/DEBIAN/postrm"

## the headphones: Switchroot's UCM profile has them as another profile of the
## card, which PulseAudio does not switch to when they are plugged in

HPS="${CPKG}/root/usr/lib/nxd/headphones"
mkdir -p "${tmp}/hp/bin"
# `pactl list cards` of a Switch Lite (LC_ALL=C), with the active profile and
# the jack to fill in
cat > "${tmp}/hp/cards" << 'CARDS'
Card #0
	Name: alsa_card.platform-70030000.hda
	Driver: module-alsa-card.c
	Profiles:
		off: Off (sinks: 0, sources: 0, priority: 0, available: yes)
	Active Profile: off
	Ports:
		[Out] HDMI1: HDMI / DisplayPort (type: HDMI, priority: 5900, latency offset: 0 usec, not available)
			Part of profile(s): output:hdmi-stereo
Card #1
	Name: alsa_card.platform-sound
	Driver: module-alsa-card.c
	Owner Module: 7
	Properties:
		alsa.card = "1"
	Profiles:
		HiFi (DummyMic, Speaker): Play HiFi quality Music (DummyMic, Speaker) (sinks: 1, sources: 1, priority: 40968, available: yes)
		HiFi (DummyMic, Headphones): Play HiFi quality Music (DummyMic, Headphones) (sinks: 1, sources: 1, priority: 40968, available: yes)
		HiFi (HeadsetMic, Speaker): Play HiFi quality Music (HeadsetMic, Speaker) (sinks: 1, sources: 1, priority: 40968, available: yes)
		HiFi (Headphones, HeadsetMic): Play HiFi quality Music (Headphones, HeadsetMic) (sinks: 1, sources: 1, priority: 40968, available: yes)
		off: Off (sinks: 0, sources: 0, priority: 0, available: yes)
	Active Profile: @ACTIVE@
	Ports:
		[Out] Speaker: Speaker playback (type: Speaker, priority: 100, latency offset: 0 usec, availability unknown)
			Part of profile(s): HiFi (DummyMic, Speaker), HiFi (HeadsetMic, Speaker)
		[Out] Headphones: Headphones playback (type: Headphones, priority: 100, latency offset: 0 usec, @HP@)
			Part of profile(s): HiFi (DummyMic, Headphones), HiFi (Headphones, HeadsetMic)
CARDS
cat > "${tmp}/hp/bin/pactl" << 'PACTL'
#!/bin/sh
case "$1" in
    list) sed -e "s/@ACTIVE@/$(cat "${HPDIR}/active")/" -e "s/@HP@/$(cat "${HPDIR}/jack")/" "${HPDIR}/cards" ;;
    set-card-profile) echo "$2|$3" > "${HPDIR}/set" ;;
esac
PACTL
chmod +x "${tmp}/hp/bin/pactl"
# jack ACTIVE JACK: the profile the script sets, or "none"
jack() {
    echo "$1" > "${tmp}/hp/active"
    echo "$2" > "${tmp}/hp/jack"
    rm -f "${tmp}/hp/set" "${tmp}/hp/state"
    HPDIR="${tmp}/hp" PATH="${tmp}/hp/bin:${PATH}" \
        NXD_HEADPHONES_STATE="${tmp}/hp/state" NXD_HEADPHONES_DEBOUNCE=0 NXD_HEADPHONES_COOLDOWN=5 \
        "${HPS}" --once 2> /dev/null
    cat "${tmp}/hp/set" 2> /dev/null || echo none
}
check "headphones plugged in: their profile" \
    test "$(jack "HiFi (DummyMic, Speaker)" available)" = "alsa_card.platform-sound|HiFi (DummyMic, Headphones)"
check "...keeping the input" \
    test "$(jack "HiFi (HeadsetMic, Speaker)" available)" = "alsa_card.platform-sound|HiFi (Headphones, HeadsetMic)"
check "taken out: the speaker's" \
    test "$(jack "HiFi (DummyMic, Headphones)" "not available")" = "alsa_card.platform-sound|HiFi (DummyMic, Speaker)"
check "...keeping the input" \
    test "$(jack "HiFi (Headphones, HeadsetMic)" "not available")" = "alsa_card.platform-sound|HiFi (HeadsetMic, Speaker)"
check "nothing when the profile is the right one already" test "$(jack "HiFi (DummyMic, Headphones)" available)" = none
check "...nor when the card is off" test "$(jack off available)" = none
check "run for each user" test -L "${CPKG}/root/usr/lib/systemd/user/default.target.wants/nxd-headphones.service"
check "...again whenever PulseAudio comes back" grep -qx 'Restart=always' "${CPKG}/root/usr/lib/systemd/user/nxd-headphones.service"
# the anti-flicker state: a state file in tmpfs (never the SD card) remembers
# the jack so a restart of the unit does not flip the profile again, and two
# switches are never closer than the cooldown
echo "HiFi (DummyMic, Speaker)" > "${tmp}/hp/active"
echo "available" > "${tmp}/hp/jack"
rm -f "${tmp}/hp/set" "${tmp}/hp/state"
HPDIR="${tmp}/hp" PATH="${tmp}/hp/bin:${PATH}" \
    NXD_HEADPHONES_STATE="${tmp}/hp/state" NXD_HEADPHONES_DEBOUNCE=0 NXD_HEADPHONES_COOLDOWN=30 \
    "${HPS}" --once 2> /dev/null
check "at start it switches the profile" \
    test "$(cat "${tmp}/hp/set" 2> /dev/null)" = "alsa_card.platform-sound|HiFi (DummyMic, Headphones)"
rm -f "${tmp}/hp/set"
HPDIR="${tmp}/hp" PATH="${tmp}/hp/bin:${PATH}" \
    NXD_HEADPHONES_STATE="${tmp}/hp/state" NXD_HEADPHONES_DEBOUNCE=0 NXD_HEADPHONES_COOLDOWN=30 \
    "${HPS}" --once 2> /dev/null
check "a restart of the unit does not switch again" test -z "$(cat "${tmp}/hp/set" 2> /dev/null)"
echo "not available" > "${tmp}/hp/jack"
echo "HiFi (DummyMic, Headphones)" > "${tmp}/hp/active"
rm -f "${tmp}/hp/set"
HPDIR="${tmp}/hp" PATH="${tmp}/hp/bin:${PATH}" \
    NXD_HEADPHONES_STATE="${tmp}/hp/state" NXD_HEADPHONES_DEBOUNCE=0 NXD_HEADPHONES_COOLDOWN=30 \
    "${HPS}" --once 2> /dev/null
check "a switch within the cooldown window is deferred" test -z "$(cat "${tmp}/hp/set" 2> /dev/null)"
HPDIR="${tmp}/hp" PATH="${tmp}/hp/bin:${PATH}" \
    NXD_HEADPHONES_STATE="${tmp}/hp/state" NXD_HEADPHONES_DEBOUNCE=0 NXD_HEADPHONES_COOLDOWN=0 \
    "${HPS}" --once 2> /dev/null
check "...and is applied once the cooldown is elapsed" \
    test "$(cat "${tmp}/hp/set" 2> /dev/null)" = "alsa_card.platform-sound|HiFi (DummyMic, Speaker)"
rm -f "${tmp}/hp/set"
check "nxd-common needs pactl" grep -qw 'pulseaudio-utils' <<< "$(dpkg-deb -f "${COMMON}" Depends)"

# the version from git, in a repository of its own
repo="${tmp}/repo"
git init -q "${repo}"
commit() { git -C "${repo}" -c user.name=t -c user.email=t@invalid commit -q --allow-empty -m "$1"; }
BUILD="${NXD_ROOT}/scripts/build-packages.sh"
version() { NXD_ROOT="${repo}" "${BUILD}" --print-version; }
commit one
commit two
check "before any tag: 0.0.0.gitN.gSHA" grep -qE '^0\.0\.0\.git2\.g[0-9a-f]{7}$' <<< "$(version)"
git -C "${repo}" tag v1.4.0
check "on a tag: its version" test "$(version)" = 1.4.0
commit three
v="$(version)"
check "after a tag: newer than it" dpkg --compare-versions "${v}" gt 1.4.0
check "...and older than the next release" dpkg --compare-versions "${v}" lt 1.4.1
commit four
check "a later commit is newer" dpkg --compare-versions "$(version)" gt "${v}"
check "outside git: 0.0.0" test "$(NXD_ROOT="${tmp}/debs" "${BUILD}" --print-version)" = 0.0.0

## nxd-update ----------------------------------------------------------------

SITE="${tmp}/site"
mkdir -p "${SITE}"
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
BASE="http://127.0.0.1:${PORT}"

# mkdeb ASSET FILE: a package whose name and version are the asset's
mkdeb() {
    local name="$1" dir version
    version="${name#*_}"
    version="${version%%_*}"
    dir="$(mktemp -d "${tmp}/deb.XXXXXX")"
    mkdir -p "${dir}/DEBIAN"
    printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: t <t@invalid>\nDescription: t\n' \
        "${name%%_*}" "${version}" > "${dir}/DEBIAN/control"
    dpkg-deb --build "${dir}" "$2" > /dev/null
}

# release REPO TAG PRERELEASE ASSET...: publishes a release with those assets
# and their SHA256SUMS ("badsum" spoils the checksum of the first .deb)
release() {
    local repo="$1" tag="$2" pre="$3" asset badsum=0 name
    shift 3
    local dir="${SITE}/dl/${repo}/${tag}" names=() assets="[]"
    mkdir -p "${dir}" "${SITE}/repos/${repo}/releases"
    for asset in "$@"; do
        if [[ "${asset}" == badsum ]]; then
            badsum=1
            continue
        fi
        [[ "${asset}" != *.deb ]] || mkdeb "${asset}" "${dir}/${asset}"
        [[ "${asset}" == *.deb ]] || echo zip > "${dir}/${asset}"
        names+=("${asset}")
    done
    (cd "${dir}" && sha256sum -- "${names[@]}" > SHA256SUMS)
    # a checksum no file has (changing one character of the real one could
    # leave it as it was)
    [[ "${badsum}" -eq 0 ]] || sed -i -E "1s/^[0-9a-f]{64}/$(printf '%064d' 0)/" "${dir}/SHA256SUMS"
    names+=(SHA256SUMS)
    for name in "${names[@]}"; do
        assets="$(jq -c --arg n "${name}" --arg u "${BASE}/dl/${repo}/${tag}/${name}" \
            --arg d "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" '. + [{name: $n, browser_download_url: $u, updated_at: $d}]' <<< "${assets}")"
    done
    jq -n --arg tag "${tag}" --argjson pre "${pre}" --argjson assets "${assets}" --arg t "$(date +%s%N)" \
        '{tag_name: $tag, prerelease: $pre, draft: false, assets: $assets, created: $t}' \
        > "${SITE}/repos/${repo}/releases/${tag}.json"
    [[ "${pre}" == true ]] || cp "${SITE}/repos/${repo}/releases/${tag}.json" "${SITE}/repos/${repo}/releases/latest"
    # the list endpoint, newest first (the server drops the query string)
    jq -s 'sort_by(.created) | reverse' "${SITE}/repos/${repo}/releases/"*.json > "${SITE}/repos/${repo}/releases/index.html"
}

release Me/nxd v1.0.0 false nxd-common_1.0.0_all.deb nxd-retrobox_1.0.0_all.deb image-installer.zip
release Me/nxd nxd-latest true nxd-common_1.0.0.git3.gabcdef0_all.deb nxd-retrobox_1.0.0.git3.gabcdef0_all.deb
release Org/core v2.0 false core_2.0_arm64.deb core_2.0_amd64.deb
release Org/bad v1.0 false bad_1.1_all.deb badsum
release Org/images v1.0 false image-installer.zip

(cd "${SITE}" && exec python3 -m http.server "${PORT}" --bind 127.0.0.1 > /dev/null 2>&1) &
server=$!
for _ in $(seq 1 50); do
    curl -fs "${BASE}/repos/Me/nxd/releases/latest" > /dev/null 2>&1 && break
    sleep 0.1
done

export NXD_GITHUB_API="${BASE}" NXD_ARCH=arm64 NXD_RELEASE_TAG_RE='debian[-_.]?13|trixie'
export NXD_RELEASES_DIR="${tmp}/lists" NXD_STATE_DIR="${tmp}/state" NXD_UPDATE_INSTALLED="${tmp}/installed"
mkdir -p "${NXD_RELEASES_DIR}"
printf '%s\n' "# nx-debian" Me/nxd > "${NXD_RELEASES_DIR}/nx-debian.list"
printf '%s\n' "Org/core core   # only its core package" Org/images > "${NXD_RELEASES_DIR}/retrobox.list"

# update [FLAGS...]: the packages nxd-update would install, by file name
update() {
    rm -rf "${tmp}/dl"
    "${UPDATE}" "$@" --download-only "${tmp}/dl" 2> "${tmp}/log" | xargs -r -n1 basename | sort | tr '\n' ' '
}

printf '%s\n' "nxd-common 0.9" "core 1.0" > "${NXD_UPDATE_INSTALLED}"
check "the newer release of what is installed" test "$(update)" = "core_2.0_arm64.deb nxd-common_1.0.0_all.deb "
check_not "not nxd-retrobox" grep -q 'nxd-retrobox' <<< "$(update)"
check "not the pre-release without the flag" grep -q 'Me/nxd v1.0.0: nxd-common' "${tmp}/log"
check "the pre-release with --allow-prereleases" \
    test "$(update --allow-prereleases)" = "core_2.0_arm64.deb nxd-common_1.0.0.git3.gabcdef0_all.deb "
check "a repository without packages is skipped" grep -q 'Org/images: no release with packages' "${tmp}/log"
printf '%s\n' "Org/core core" Org/missing Org/images > "${NXD_RELEASES_DIR}/retrobox.list"
check "a repository the API cannot read does not stop the others" grep -q 'core_2.0_arm64.deb' <<< "$(update --allow-prereleases)"
check "...and says what GitHub answered" grep -q '/repos/Org/missing/releases?per_page=30: HTTP 404' "${tmp}/log"
printf '%s\n' "Org/core core   # only its core package" Org/images > "${NXD_RELEASES_DIR}/retrobox.list"

printf '%s\n' "nxd-common 1.0.0" "nxd-retrobox 1.0.0" "core 2.0" > "${NXD_UPDATE_INSTALLED}"
check "nothing when everything is up to date" test -z "$(update)"
check "...and it says so" grep -q 'nxd-common 1.0.0 is up to date' "${tmp}/log"
check "a pre-release after the release is newer" \
    test "$(update --allow-prereleases)" = "nxd-common_1.0.0.git3.gabcdef0_all.deb nxd-retrobox_1.0.0.git3.gabcdef0_all.deb "

# the release installed last time is not downloaded again
mkdir -p "${NXD_STATE_DIR}"
cp "${tmp}/dl/Me_nxd/state" "${NXD_STATE_DIR}/Me_nxd"
update --allow-prereleases > /dev/null
check "a release installed before is not downloaded again" grep -q 'Me/nxd nxd-latest (pre-release): up to date' "${tmp}/log"

# the packages a list names come even when they are not installed yet
printf '%s\n' "nxd-common 1.0.0" "nxd-retrobox 1.0.0" > "${NXD_UPDATE_INSTALLED}"
check "a package the list names is installed when it is not yet" test "$(update)" = "core_2.0_arm64.deb "
check "...and said to be new" grep -q 'Org/core v2.0: core 2.0 (new)' "${tmp}/log"

# a release whose files are being replaced (nx-debian's nxd-latest on a push)
release Org/two v1 false two_1.0_all.deb two_1.5_all.deb
release Org/half v1 false half_2.0_all.deb
sed -i '/half_2.0_all.deb/d' "${SITE}/dl/Org/half/v1/SHA256SUMS"
printf '%s\n' "two 0.9" "half 1.0" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/two Org/half > "${NXD_RELEASES_DIR}/retrobox.list"
rm -rf "${NXD_STATE_DIR}"
check "with two versions of a package, the highest" test "$(update)" = "two_1.5_all.deb "
check "a package not in SHA256SUMS yet is skipped, nothing stops" grep -q 'half_2.0_all.deb is not in its SHA256SUMS yet' "${tmp}/log"
check_not "...and that release is not remembered, so the next run takes it" test -e "${tmp}/dl/Org_half/state"
# --allow-prereleases goes by the date of the packages: a pre-release made
# long ago whose files were just replaced wins over a release made after it
release Org/roll rolling true roll_1.1_all.deb
release Org/roll v1.0 false roll_1.0_all.deb
jq --arg d "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%S.%NZ)" '.assets |= map(.updated_at = $d)' \
    "${SITE}/repos/Org/roll/releases/rolling.json" > "${tmp}/rolling.json"
mv "${tmp}/rolling.json" "${SITE}/repos/Org/roll/releases/rolling.json"
jq -s 'sort_by(.created) | reverse' "${SITE}/repos/Org/roll/releases/"*.json > "${SITE}/repos/Org/roll/releases/index.html"
printf '%s\n' "roll 0.5" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/roll > "${NXD_RELEASES_DIR}/retrobox.list"
check "the release with the newest packages, not the newest release" test "$(update --allow-prereleases)" = "roll_1.1_all.deb "
check "...while without the flag, the release" test "$(update)" = "roll_1.0_all.deb "

# a repository with pre-releases only: GitHub answers /releases/latest 404,
# which is no reason to warn
release Org/pre beta true pre_2.0_all.deb
printf '%s\n' "pre 1.0" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/pre > "${NXD_RELEASES_DIR}/retrobox.list"
check "pre-releases only, without the flag: nothing" test -z "$(update)"
check "...saying that the flag would take them" grep -q 'Org/pre: no release with packages (pre-releases need' "${tmp}/log"
check_not "...and no warning" grep -q 'warning' "${tmp}/log"
check "...and with the flag, the pre-release" test "$(update --allow-prereleases)" = "pre_2.0_all.deb "

# running itself again (sudo, systemd-inhibit) keeps the options: the option
# loop consumes "$@"
if [[ "${EUID}" -ne 0 ]]; then
    mkdir -p "${tmp}/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\n' "${tmp}/sudo-args" > "${tmp}/bin/sudo"
    chmod +x "${tmp}/bin/sudo"
    PATH="${tmp}/bin:${PATH}" "${UPDATE}" --allow-prereleases > /dev/null 2>&1 || true
    check "through sudo, with the options it was given" grep -qx -- '--allow-prereleases' "${tmp}/sudo-args"
fi

printf '%s\n' "bad 1.0" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/bad > "${NXD_RELEASES_DIR}/retrobox.list"
check_not "a package that does not match SHA256SUMS stops it" \
    "${UPDATE}" --download-only "${tmp}/dl2"
check "...saying why" bash -c "'${UPDATE}' --download-only '${tmp}/dl3' 2>&1 | grep -q 'does not match the SHA256SUMS'"

PIN="${NXD_ROOT}/packages/nxd-common/root/etc/apt/preferences.d/50-nxd-no-l4t-meta.pref"
check "Switchroot's essential metapackage is never installed" grep -qx 'Package: nintendo-switch-meta switch-l4t-repo' "${PIN}"
check "...pinned below zero" grep -qx 'Pin-Priority: -1' "${PIN}"
check "nxd-update installs no Recommends, as the image is built" grep -q 'APT::Install-Recommends=false' "${UPDATE}"
check "--help works without root" "${UPDATE}" --help
check_not "an unknown option is refused" "${UPDATE}" --nope

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
