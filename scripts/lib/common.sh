#!/usr/bin/env bash
# Shared helpers for the nxd scripts. Sourced, never executed.

NXD_ROOT="${NXD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
NXD_CONFIG_DIR="${NXD_CONFIG_DIR:-${NXD_ROOT}/config}"

log() { printf '[nxd] %s\n' "$*" >&2; }
warn() { printf '[nxd] WARNING: %s\n' "$*" >&2; }
die() {
    printf '[nxd] ERROR: %s\n' "$*" >&2
    exit 1
}

# need_cmd COMMAND HINT
need_cmd() {
    command -v "$1" > /dev/null 2>&1 || die "missing command '$1': $2"
}

# Load config/nxd.conf. Every setting there is "${NXD_X:-default}", so an
# environment variable of the same name always wins.
load_config() {
    [[ -f "${NXD_CONFIG_DIR}/nxd.conf" ]] || die "no config at ${NXD_CONFIG_DIR}/nxd.conf"
    # shellcheck source=/dev/null
    . "${NXD_CONFIG_DIR}/nxd.conf"
}

# read_list FILE: the package names of a list, one per line. '#' starts a
# comment; blank lines are ignored.
read_list() {
    local file="$1" line
    [[ -f "${file}" ]] || die "package list not found: ${file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
        fi
    done < "${file}"
}

# list_names: the names of the variants (files of config/variants).
list_variants() {
    local conf
    for conf in "${NXD_CONFIG_DIR}"/variants/*.conf; do
        [[ -f "${conf}" ]] || continue
        basename "${conf}" .conf
    done
}

# variant_lists VARIANT: the package lists of a variant, in order.
variant_lists() {
    local variant="$1" conf lists
    conf="${NXD_CONFIG_DIR}/variants/${variant}.conf"
    [[ -f "${conf}" ]] || die "unknown variant '${variant}' (known: $(list_variants | tr '\n' ' '))"
    lists="$(
        NXD_VARIANT_LISTS=""
        # shellcheck source=/dev/null
        . "${conf}"
        printf '%s' "${NXD_VARIANT_LISTS}"
    )"
    [[ -n "${lists}" ]] || die "variant '${variant}' sets no NXD_VARIANT_LISTS"
    printf '%s\n' "${lists}" | tr -s '[:space:]' '\n'
}

# variant_packages VARIANT: every package of a variant, once, in list order.
variant_packages() {
    local list
    while IFS= read -r list; do
        [[ -n "${list}" ]] || continue
        read_list "${NXD_CONFIG_DIR}/packages/${list}.list"
    done < <(variant_lists "$1") | awk '!seen[$0]++'
}

# url_host URL: the host an apt "origin" pin matches ("" for file: URLs).
url_host() {
    local url="$1" host
    case "${url}" in
        file:*) host="" ;;
        *)
            host="${url#*://}"
            host="${host%%/*}"
            host="${host%%:*}"
            ;;
    esac
    printf '%s' "${host}"
}

# render_pins HOST: config/apt/l4t.pref with the repository's host filled in.
render_pins() {
    sed "s|@L4T_HOST@|$1|g" "${NXD_CONFIG_DIR}/apt/l4t.pref"
}

# key_fingerprint FILE: fingerprint of the first (primary) key of a key file.
key_fingerprint() {
    need_cmd gpg "install gnupg"
    gpg --batch --show-keys --with-colons "$1" 2> /dev/null |
        awk -F: '$1 == "fpr" { print toupper($10); exit }'
}

# verify_key FILE FINGERPRINT: abort unless the key file is the expected key.
verify_key() {
    local file="$1" expected="${2^^}" found
    [[ -f "${file}" ]] || die "key file not found: ${file}"
    found="$(key_fingerprint "${file}")"
    [[ "${found}" == "${expected}" ]] ||
        die "${file}: fingerprint ${found:-<none>} is not the expected ${expected}"
}

# l4t_source_line ARCH KEYFILE_IN_TARGET COMPONENT: the apt line of the L4T repo.
l4t_source_line() {
    printf 'deb [arch=%s signed-by=%s] %s %s %s\n' \
        "$1" "$2" "${NXD_L4T_URL}" "${NXD_L4T_SUITE}" "$3"
}

# l4t_sources_file ARCH KEYFILE_IN_TARGET COMPONENT: the L4T repository as a
# deb822 file, for the rootfs (where apt resolves the key path itself).
l4t_sources_file() {
    cat << EOF
Types: deb
URIs: ${NXD_L4T_URL}
Suites: ${NXD_L4T_SUITE}
Components: $3
Architectures: $1
Signed-By: $2
EOF
}

# render_compat_pins: pins of the compat suite. The listed packages may be
# installed from it, everything else in it never is. Prints nothing when the
# compat suite is off.
render_compat_pins() {
    [[ -n "${NXD_COMPAT_SUITE}" ]] || return 0
    if [[ -n "${NXD_COMPAT_PACKAGES}" ]]; then
        printf 'Package: %s\nPin: release n=%s\nPin-Priority: 100\n\n' \
            "${NXD_COMPAT_PACKAGES}" "${NXD_COMPAT_SUITE}"
    fi
    printf 'Package: *\nPin: release n=%s\nPin-Priority: -1\n' "${NXD_COMPAT_SUITE}"
}

# compat_sources_file ARCH: the compat suite as a deb822 file (verified with
# the archive keyring installed in the rootfs).
compat_sources_file() {
    [[ -n "${NXD_COMPAT_SUITE}" ]] || return 0
    cat << EOF
Types: deb
URIs: ${NXD_MIRROR}
Suites: ${NXD_COMPAT_SUITE}
Components: ${NXD_COMPONENTS}
Architectures: $1
EOF
}

# variant_setting VARIANT NAME: the value of NXD_NAME set by the variant's conf
# file, empty when it does not set it.
variant_setting() {
    local file="${NXD_CONFIG_DIR}/variants/$1.conf"
    [[ -f "${file}" ]] || die "unknown variant: $1"
    (
        # shellcheck source=/dev/null
        . "${file}"
        printf '%s' "${!2:-}"
    )
}

# dpkg_excludes_file VARIANT: the dpkg.cfg.d file that keeps the variant's
# NXD_PATH_EXCLUDES out of the image (docs, man pages, kernel headers...).
# Nothing is printed when the variant excludes nothing.
dpkg_excludes_file() {
    local excludes includes pattern
    local -a patterns
    excludes="$(variant_setting "$1" NXD_PATH_EXCLUDES)"
    includes="$(variant_setting "$1" NXD_PATH_INCLUDES)"
    [[ -n "${excludes}" ]] || return 0
    printf '# Written by nxd: paths this variant does not ship.\n'
    # read -a splits on spaces without expanding the globs of the patterns.
    read -r -a patterns <<< "${excludes}"
    for pattern in "${patterns[@]}"; do
        printf 'path-exclude=%s\n' "${pattern}"
    done
    read -r -a patterns <<< "${includes}"
    for pattern in "${patterns[@]}"; do
        printf 'path-include=%s\n' "${pattern}"
    done
}

# hand_back_ownership DIR: when running as root, give DIR to the owner of the
# directory it lives in, so it can be read and written without sudo.
hand_back_ownership() {
    local dir="$1" owner
    [[ "${EUID}" -eq 0 ]] || return 0
    owner="$(stat -c '%u:%g' "$(dirname "${dir}")")"
    [[ "${owner}" == "0:0" ]] || chown -R "${owner}" "${dir}"
}
