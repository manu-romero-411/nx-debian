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
check "the session script is executable" grep -q '^-rwxr-xr-x .*\./usr/lib/nxd/retrobox-session$' <<< "$(dpkg-deb -c "${RETRO}")"
check "the triggers are in nxd-common" grep -qx './triggers' <<< "$(dpkg-deb --ctrl-tarfile "${COMMON}" | tar -t)"
check "--variant xfce builds nxd-common only" bash -c \
    "'${NXD_ROOT}/scripts/build-packages.sh' --version 1 --variant xfce '${tmp}/xfce' && test \"\$(ls '${tmp}/xfce')\" = nxd-common_1_all.deb"
check "--variant retrobox builds both" bash -c \
    "'${NXD_ROOT}/scripts/build-packages.sh' --version 1 --variant retrobox '${tmp}/rb' && test \"\$(ls '${tmp}/rb' | wc -l)\" -eq 2"
check_not "a version that is not one is refused" "${NXD_ROOT}/scripts/build-packages.sh" --version v1 "${tmp}/bad"

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
printf '%s\n' Org/core Org/images > "${NXD_RELEASES_DIR}/retrobox.list"

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

printf '%s\n' "bad 1.0" > "${NXD_UPDATE_INSTALLED}"
printf '%s\n' Org/bad > "${NXD_RELEASES_DIR}/retrobox.list"
check_not "a package that does not match SHA256SUMS stops it" \
    "${UPDATE}" --download-only "${tmp}/dl2"
check "...saying why" bash -c "'${UPDATE}' --download-only '${tmp}/dl3' 2>&1 | grep -q 'does not match the SHA256SUMS'"

check "--help works without root" "${UPDATE}" --help
check_not "an unknown option is refused" "${UPDATE}" --nope

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
