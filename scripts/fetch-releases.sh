#!/usr/bin/env bash
# Downloads the .deb packages of the latest release of every repository in a
# list (config/releases/NAME.list) and verifies them against the SHA256SUMS of
# the release. The asset choice follows the install.sh of
# retroboxproject.github.io: a package built for this CPU and Debian release,
# else a generic one for the CPU, else an architecture-independent one.
#
#   fetch-releases.sh [--prereleases] NAME DEST_DIR
#
# Only the releases GitHub does not mark as pre-releases are used, unless
# --prereleases (or NXD_PRERELEASES=1) asks for the newest release of each
# repository, a pre-release or not: Retrobox keeps adding features, and its
# releases lag behind them until it is finished.
#
# $GITHUB_TOKEN, when set, avoids the API rate limit. $NXD_GITHUB_API points
# the script at another API (the tests use a local one).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

PRERELEASES="${NXD_PRERELEASES:-0}"
if [[ "${1:-}" == "--prereleases" ]]; then
    PRERELEASES=1
    shift
fi
LIST_NAME="${1:?usage: fetch-releases.sh [--prereleases] NAME DEST_DIR}"
DEST="${2:?usage: fetch-releases.sh [--prereleases] NAME DEST_DIR}"
LIST="${NXD_CONFIG_DIR}/releases/${LIST_NAME}.list"
[[ -f "${LIST}" ]] || die "no release list: ${LIST}"
need_cmd curl "install curl"
need_cmd jq "install jq"
need_cmd sha256sum "install coreutils"

API="${NXD_GITHUB_API:-https://api.github.com}"
# Release assets that must never be installed.
EXCLUDE_RE='dbgsym|debuginfo|debugsource'
# Any distro marker in an asset name: an asset carrying one is used only when
# it is the one of this Debian release; assets without any are generic.
ANY_TAG_RE='(debian|ubuntu|fedora)[-_.]?[0-9]|[._-]fc[0-9]+|[._-]el[0-9]+|trixie|bookworm|bullseye|forky|focal|jammy|noble|resolute|oracular|plucky|questing'
TAG_RE="${NXD_RELEASE_TAG_RE}"

api_get() {
    local -a headers=(-H "Accept: application/vnd.github+json")
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl -fsSL "${headers[@]}" "$1"
}

# The regexes for the CPU, best first.
arch_regexes() {
    printf '%s\n' "[_.-]${NXD_ARCH}\\.deb\$"
    printf '%s\n' '[_.-]all\.deb$'
}

# select_assets: names on stdin; prints the ones to install.
select_assets() {
    local name arch_re
    local -a all=() tagged=() generic=()
    mapfile -t all
    while IFS= read -r arch_re; do
        tagged=()
        generic=()
        for name in "${all[@]}"; do
            [[ "${name,,}" =~ ${arch_re} && ! "${name,,}" =~ ${EXCLUDE_RE} ]] || continue
            if [[ "${name,,}" =~ ${TAG_RE} ]]; then
                tagged+=("${name}")
            elif [[ ! "${name,,}" =~ ${ANY_TAG_RE} ]]; then
                generic+=("${name}")
            fi
        done
        if ((${#tagged[@]} > 0)); then
            printf '%s\n' "${tagged[@]}"
            return 0
        fi
        if ((${#generic[@]} > 0)); then
            printf '%s\n' "${generic[@]}"
            return 0
        fi
    done < <(arch_regexes)
    return 1
}

# verify FILE SUMS: FILE is listed in SUMS ("<sha256>  <name>") and matches.
verify() {
    local file="$1" sums="$2" name expected actual
    name="${file##*/}"
    expected="$(awk -v f="${name}" '
        { gsub(/\r/, ""); n = $2; sub(/^\*/, "", n); sub(/^.*\//, "", n) }
        n == f { print tolower($1); exit }' "${sums}")"
    [[ -n "${expected}" ]] || die "${name} is not in the SHA256SUMS of its release"
    actual="$(sha256sum "${file}")"
    actual="${actual%% *}"
    [[ "${actual}" == "${expected}" ]] ||
        die "checksum mismatch for ${name} (expected ${expected}, got ${actual})"
}

mkdir -p "${DEST}"
while IFS= read -r repo; do
    repo="${repo%%#*}"
    repo="${repo//[[:space:]]/}"
    [[ -n "${repo}" ]] || continue
    if [[ "${PRERELEASES}" == "1" ]]; then
        # the newest published release, pre-release or not (never a draft)
        json="$(api_get "${API}/repos/${repo}/releases?per_page=30" | jq '[.[] | select(.draft != true)][0]')" ||
            die "cannot read the releases of ${repo} (rate limited? set GITHUB_TOKEN)"
    else
        # GitHub's "latest" is the newest release that is not a pre-release
        json="$(api_get "${API}/repos/${repo}/releases/latest" 2> /dev/null)" ||
            die "${repo} has no release that is not a pre-release (or it cannot be read: rate limited? set GITHUB_TOKEN); --prereleases allows pre-releases"
    fi
    tag="$(jq -r '.tag_name // empty' <<< "${json}")"
    [[ -n "${tag}" ]] || die "${repo} has no release"
    kind="$(jq -r 'if .prerelease then " (pre-release)" else "" end' <<< "${json}")"
    mapfile -t names < <(jq -r '.assets[].name' <<< "${json}")
    mapfile -t chosen < <(printf '%s\n' "${names[@]}" | select_assets) || true
    if ((${#chosen[@]} == 0)); then
        warn "assets of ${repo} ${tag}: ${names[*]}"
        die "${repo} ${tag} has no .deb for ${NXD_ARCH} (looking for ${NXD_ARCH} or all, tag ${TAG_RE})"
    fi
    sums_name="$(printf '%s\n' "${names[@]}" | grep -iE '^sha256sums?(\.txt)?$' | head -n 1 || true)"
    [[ -n "${sums_name}" ]] || die "${repo} ${tag} has no SHA256SUMS: refusing to install unverified packages"
    sums="${DEST}/${repo##*/}.sha256sums"
    curl -fsSL -o "${sums}" "$(jq -r --arg n "${sums_name}" '.assets[] | select(.name == $n) | .browser_download_url' <<< "${json}")"
    for name in "${chosen[@]}"; do
        log "${repo} ${tag}${kind}: ${name}"
        curl -fsSL -o "${DEST}/${name}" \
            "$(jq -r --arg n "${name}" '.assets[] | select(.name == $n) | .browser_download_url' <<< "${json}")"
        verify "${DEST}/${name}" "${sums}"
    done
    rm -f "${sums}"
done < "${LIST}"
chmod 644 "${DEST}"/*.deb
