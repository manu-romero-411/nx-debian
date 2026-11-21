#!/usr/bin/env bash
# Test of fetch-releases.sh against a fake GitHub API served over http on
# localhost: asset choice, checksum verification, pre-releases only on request.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
FETCH="${NXD_ROOT}/scripts/fetch-releases.sh"

for tool in curl jq dpkg-deb python3; do
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

SITE="${tmp}/site"
mkdir -p "${SITE}"

# mkdeb NAME FILE: a one-file package named like a release asset.
mkdeb() {
    local name="$1" dir
    dir="$(mktemp -d "${tmp}/deb.XXXXXX")"
    mkdir -p "${dir}/DEBIAN"
    printf 'Package: %s\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@invalid>\nDescription: t\n' \
        "${name%%_*}" > "${dir}/DEBIAN/control"
    dpkg-deb --build "${dir}" "$2" > /dev/null
}

PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
BASE="http://127.0.0.1:${PORT}"

# release REPO TAG PRERELEASE ASSET...: publishes a release with those assets
# (a SHA256SUMS is added unless the asset list has "nosums").
release() {
    local repo="$1" tag="$2" pre="$3" asset
    shift 3
    local dir="${SITE}/dl/${repo}"
    mkdir -p "${dir}" "${SITE}/repos/${repo}/releases"
    local sums=1 names=()
    for asset in "$@"; do
        if [[ "${asset}" == "nosums" ]]; then
            sums=0
            continue
        fi
        mkdeb "${asset}" "${dir}/${asset}"
        names+=("${asset}")
    done
    if [[ "${sums}" -eq 1 ]]; then
        (cd "${dir}" && sha256sum -- *.deb > SHA256SUMS)
        names+=("SHA256SUMS")
    fi
    local assets="[]" name
    for name in "${names[@]}"; do
        assets="$(jq -c --arg n "${name}" --arg u "${BASE}/dl/${repo}/${name}" '. + [{name: $n, browser_download_url: $u}]' <<< "${assets}")"
    done
    jq -n --arg tag "${tag}" --argjson pre "${pre}" --argjson assets "${assets}" \
        '{tag_name: $tag, prerelease: $pre, assets: $assets}' > "${SITE}/repos/${repo}/releases/${tag}.json"
    if [[ "${pre}" == "false" ]]; then
        cp "${SITE}/repos/${repo}/releases/${tag}.json" "${SITE}/repos/${repo}/releases/latest"
    fi
    # The list endpoint, newest first (the server drops the query string, so
    # the directory index stands for it), for --prereleases.
    local -a files
    mapfile -t files < <(find "${SITE}/repos/${repo}/releases" -name '*.json' | sort -rV)
    jq -s '.' "${files[@]}" > "${SITE}/repos/${repo}/releases/index.html"
}

release Org/core v1.0 false core_1.0_all.deb core-dbgsym_1.0_all.deb
release Org/es v2.0 false es_2.0_arm64.deb es_2.0_amd64.deb es_2.0_debian13_arm64.deb es_2.0_ubuntu24.04_arm64.deb es_2.0_fedora.rpm
release Org/generic v1.0 false generic_1.0_arm64.deb generic_1.0_ubuntu24.04_arm64.deb
release Org/pre v0.1.1 true pre_0.1.1_all.deb
release Org/both v1.0 false both_1.0_all.deb
release Org/both v1.1 true both_1.1_all.deb
release Org/nosums v1.0 false nosums nosums_1.0_all.deb
release Org/noarch v1.0 false noarch_1.0_amd64.deb
release Org/multi v1.0 false multi-common_1.0_all.deb multi-labwc_1.0_all.deb multi-openbox_1.0_all.deb

(cd "${SITE}" && exec python3 -m http.server "${PORT}" --bind 127.0.0.1 > /dev/null 2>&1) &
server=$!
for _ in $(seq 1 50); do
    curl -fs "${BASE}/repos/Org/core/releases/latest" > /dev/null 2>&1 && break
    sleep 0.1
done

CONFIG="${tmp}/config"
mkdir -p "${CONFIG}/releases"
cp "${NXD_ROOT}/config/nxd.conf" "${CONFIG}/nxd.conf"
export NXD_CONFIG_DIR="${CONFIG}"
export NXD_GITHUB_API="${BASE}"
export NXD_ARCH=arm64

export NXD_RELEASE_LISTS_DIR="${CONFIG}/releases"
list() { printf '%s\n' "$@" > "${CONFIG}/releases/t.list"; }
fetch() { rm -rf "${tmp}/out"; "${FETCH}" t "${tmp}/out"; }
have() { [[ -f "${tmp}/out/$1" ]]; }

list "Org/core"
check "an arch-independent package is used when there is no arm64 one" bash -c "$(declare -f fetch have); FETCH='${FETCH}'; tmp='${tmp}'; fetch && have core_1.0_all.deb"
check "dbgsym packages are left out" bash -c "$(declare -f fetch have); FETCH='${FETCH}'; tmp='${tmp}'; fetch; ! have core-dbgsym_1.0_all.deb"

list "Org/es"
fetch > /dev/null 2>&1 || true
check "the package for this Debian wins" have es_2.0_debian13_arm64.deb
check "other distros' packages are skipped" test ! -f "${tmp}/out/es_2.0_ubuntu24.04_arm64.deb"
check "the generic arm64 one is not mixed in" test ! -f "${tmp}/out/es_2.0_arm64.deb"

list "Org/generic"
fetch > /dev/null 2>&1 || true
check "a generic package is used when none is tagged" have generic_1.0_arm64.deb
check "a package of another distro is not used" test ! -f "${tmp}/out/generic_1.0_ubuntu24.04_arm64.deb"

fetch_pre() { rm -rf "${tmp}/out"; "${FETCH}" --prereleases t "${tmp}/out"; }
list "Org/pre"
check_not "a repository with only a pre-release is refused by default" fetch
check "...and used with --prereleases" bash -c "$(declare -f fetch_pre have); FETCH='${FETCH}'; tmp='${tmp}'; fetch_pre && have pre_0.1.1_all.deb"
check "NXD_PRERELEASES=1 does the same as the flag" bash -c "$(declare -f fetch have); FETCH='${FETCH}'; tmp='${tmp}'; NXD_PRERELEASES=1 fetch && have pre_0.1.1_all.deb"
list "Org/both"
fetch > /dev/null 2>&1 || true
check "by default the release is used, not the newer pre-release" have both_1.0_all.deb
check "...and the pre-release is not mixed in" test ! -f "${tmp}/out/both_1.1_all.deb"
fetch_pre > /dev/null 2>&1 || true
check "--prereleases takes the newest, the pre-release" have both_1.1_all.deb
check "...instead of the release" test ! -f "${tmp}/out/both_1.0_all.deb"

list "Org/nosums"
check_not "a release without checksums is refused" fetch
list "Org/noarch"
check_not "a release without a package for the CPU is refused" fetch

# A corrupted download must be caught.
list "Org/core"
printf 'tampered' >> "${SITE}/dl/Org/core/core_1.0_all.deb"
check_not "a package that does not match its checksum is refused" fetch

# The list takes comments and blank lines, and several repositories in order.
release Org/core v1.0 false core_1.0_all.deb
list "# the components" "" "Org/core   # first" "Org/es"
fetch > /dev/null 2>&1 || true
check "a list with comments and two repositories gives both" bash -c "[[ -f '${tmp}/out/core_1.0_all.deb' && -f '${tmp}/out/es_2.0_debian13_arm64.deb' ]]"

# After a repository, the packages to take from it.
list "Org/multi multi-common multi-openbox   # not its labwc one"
fetch > /dev/null 2>&1 || true
check "the packages a line names are taken" bash -c "[[ -f '${tmp}/out/multi-common_1.0_all.deb' && -f '${tmp}/out/multi-openbox_1.0_all.deb' ]]"
check "...and only those" test ! -f "${tmp}/out/multi-labwc_1.0_all.deb"
list "Org/multi"
fetch > /dev/null 2>&1 || true
check "without names, all of them" have multi-labwc_1.0_all.deb
list "Org/multi multi-none"
check_not "names that match no package are refused" fetch

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
