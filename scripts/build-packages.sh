#!/usr/bin/env bash
# Builds the packages of nx-debian (packages/<name>/) as .deb files: nxd-common,
# the files of every image, and nxd-<variant>, the files of one variant.
#
#   build-packages.sh [--version V] [--variant NAME [--with PACKAGE]...] DEST_DIR
#   build-packages.sh --print-version
#
# Each packages/<name>/ has root/ (the files, as they go in /) and DEBIAN/
# (control.in, whose @VERSION@ is replaced, and the maintainer scripts and
# triggers, copied as they are). Every file under root/etc is a conffile.
#
# Without --variant, every package is built; with it, nxd-common, nxd-NAME
# (if there is one) and the ones --with names (one per --with: what the
# variant's extra apt repositories need, their REPO_NEEDS). The version, unless --version gives one, is the
# one of a continuous build (the rule of .github/scripts/continuous-version.sh,
# as the CI's): the last release's, from the highest vX.Y or vX.Y.Z tag (a
# missing patch is 0; no tag: 0.0.0), with the UTC time of the build as one
# more number (0.7.9.20261127093012): above that release, below the next one,
# and each build above the one before. Outside a git checkout: 0.0.0.TIME.
# NXD_BUILD_STAMP sets the time (tests).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

PACKAGES_DIR="${NXD_PACKAGES_DIR:-${NXD_ROOT}/packages}"
VERSION=""
VARIANT=""
DEST=""
PRINT_VERSION=0
WITH=()

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --variant) VARIANT="${2:?--variant needs a value}"; shift 2 ;;
        --with) WITH+=("${2:?--with needs a value}"); shift 2 ;;
        --print-version) PRINT_VERSION=1; shift ;;
        -h | --help) usage; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) DEST="$1"; shift ;;
    esac
done

# git in the checkout, also as root on a checkout of another user (sudo, a
# container), which git otherwise refuses
repo_git() {
    git -c safe.directory="${NXD_ROOT}" -C "${NXD_ROOT}" "$@"
}

# git_version: the version of the checkout (see the header)
git_version() {
    local last base
    last=""
    if repo_git rev-parse --git-dir > /dev/null 2>&1; then
        last="$(repo_git tag --list 'v[0-9]*' |
            grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n 1 || true)"
    fi
    base="${last#v}"
    base="${base:-0.0.0}"
    [[ "${base}" == *.*.* ]] || base="${base}.0"
    printf '%s.%s\n' "${base}" "${NXD_BUILD_STAMP:-$(date -u +%Y%m%d%H%M%S)}"
}

[[ -n "${VERSION}" ]] || VERSION="$(git_version)"
[[ "${VERSION}" =~ ^[0-9][A-Za-z0-9.+~]*$ ]] || die "not a package version: ${VERSION}"
if [[ "${PRINT_VERSION}" -eq 1 ]]; then
    echo "${VERSION}"
    exit 0
fi
[[ -n "${DEST}" ]] || { usage >&2; exit 2; }
need_cmd dpkg-deb "install dpkg (or build in a container: sudo ./nxd container build)"

names=(nxd-common)
if [[ -n "${VARIANT}" ]]; then
    [[ ! -d "${PACKAGES_DIR}/nxd-${VARIANT}" ]] || names+=("nxd-${VARIANT}")
    for name in "${WITH[@]}"; do
        [[ -d "${PACKAGES_DIR}/${name}" ]] || die "--with: no package ${name} in ${PACKAGES_DIR}"
        names+=("${name}")
    done
else
    for dir in "${PACKAGES_DIR}"/nxd-*/; do
        name="$(basename "${dir}")"
        [[ "${name}" == nxd-common ]] || names+=("${name}")
    done
fi

# The files get the date of the last commit, so that two builds of one commit
# are the same file.
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    SOURCE_DATE_EPOCH="$(repo_git log -1 --format=%ct 2> /dev/null || date +%s)"
fi
export SOURCE_DATE_EPOCH

mkdir -p "${DEST}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# build NAME: packages/NAME -> DEST/NAME_VERSION_all.deb
build() {
    local name="$1" src="${PACKAGES_DIR}/$1" tree="${work}/$1" file size
    [[ -f "${src}/DEBIAN/control.in" ]] || die "${src} has no DEBIAN/control.in"
    mkdir -p "${tree}/DEBIAN"
    if [[ -d "${src}/root" ]]; then
        cp -a "${src}/root/." "${tree}/"
    fi
    # what git does not keep: the permissions are the usual ones, executables stay so
    chmod -R u+rwX,go+rX,go-w "${tree}"
    # sudo wants its rules read-only (0440)
    if [[ -d "${tree}/etc/sudoers.d" ]]; then
        find "${tree}/etc/sudoers.d" -type f -exec chmod 0440 {} +
    fi
    mkdir -p "${tree}/usr/share/doc/${name}"
    install -m 644 "${NXD_ROOT}/LICENSE" "${tree}/usr/share/doc/${name}/copyright"
    for file in "${src}"/DEBIAN/*; do
        case "${file##*/}" in
            control.in) ;;
            preinst | postinst | prerm | postrm) install -m 755 "${file}" "${tree}/DEBIAN/" ;;
            *) install -m 644 "${file}" "${tree}/DEBIAN/" ;;
        esac
    done
    if [[ -d "${tree}/etc" ]]; then
        (cd "${tree}" && find etc -type f | sort | sed 's|^|/|') > "${tree}/DEBIAN/conffiles"
        chmod 644 "${tree}/DEBIAN/conffiles"
    fi
    (cd "${tree}" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z | xargs -0 -r md5sum) \
        > "${tree}/DEBIAN/md5sums"
    size="$(du -sk --exclude=DEBIAN "${tree}" | cut -f1)"
    sed -e "s/@VERSION@/${VERSION}/g" "${src}/DEBIAN/control.in" > "${tree}/DEBIAN/control"
    echo "Installed-Size: ${size}" >> "${tree}/DEBIAN/control"
    chmod 644 "${tree}/DEBIAN/control" "${tree}/DEBIAN/md5sums"
    find "${tree}" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
    file="${DEST}/${name}_${VERSION}_all.deb"
    dpkg-deb --root-owner-group -Zxz --build "${tree}" "${file}" > /dev/null
    log "package: ${file}"
}

for name in "${names[@]}"; do
    build "${name}"
done
