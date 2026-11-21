#!/usr/bin/env bash
# Test of nx-debian's own packages: what build-packages.sh (nxd debs) puts in
# them, and which packages nxd-update takes from GitHub releases, against a
# fake GitHub API served over http on localhost (--download-only: no apt).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
UPDATE="${NXD_ROOT}/packages/nxd-common/root/usr/sbin/nxd-update"

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
check "nxd-update is executable" grep -q '^-rwxr-xr-x .*\./usr/sbin/nxd-update$' <<< "$(dpkg-deb -c "${COMMON}")"
check "the session's step is executable" grep -q '^-rwxr-xr-x .*\./etc/retrobox-system-settings/session.d/50-nxd-emulationstation$' <<< "$(dpkg-deb -c "${RETRO}")"
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
check "...by a unit nxd-common enables" grep -q 'unit=nxd-nvpmodel-restore.service' "${CPKG}/DEBIAN/postinst"
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
        assets="$(jq -c --arg n "${name}" --arg u "${BASE}/dl/${repo}/${tag}/${name}" '. + [{name: $n, browser_download_url: $u}]' <<< "${assets}")"
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

printf '%s\n' "bad 1.0" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/bad > "${NXD_RELEASES_DIR}/retrobox.list"
check_not "a package that does not match SHA256SUMS stops it" \
    "${UPDATE}" --download-only "${tmp}/dl2"
check "...saying why" bash -c "'${UPDATE}' --download-only '${tmp}/dl3' 2>&1 | grep -q 'does not match the SHA256SUMS'"

check "--help works without root" "${UPDATE}" --help
check_not "an unknown option is refused" "${UPDATE}" --nope

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
