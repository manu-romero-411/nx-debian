#!/usr/bin/env bash
# Builds the packages of nx-debian (packages/<name>/) as .deb files: nxd-common,
# the files of every image, and nxd-<variant>, the files of one variant.
#
#   build-packages.sh [--version V] [--variant NAME] DEST_DIR
#   build-packages.sh --print-version
#
# Each packages/<name>/ has root/ (the files, as they go in /) and DEBIAN/
# (control.in, whose @VERSION@ is replaced, and the maintainer scripts and
# triggers, copied as they are). Every file under root/etc is a conffile.
#
# Without --variant, every package is built; with it, nxd-common and
# nxd-NAME (if there is one). The version, unless --version gives one, comes
# from git: X.Y.Z on a vX.Y.Z tag, X.Y.Z.gitN.gSHA after it (N commits later,
# so newer than X.Y.Z and older than the next release), 0.0.0.gitN.gSHA before
# the first tag, 0.0.0 outside a git checkout.
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

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --variant) VARIANT="${2:?--variant needs a value}"; shift 2 ;;
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
    local tag base count sha
    if ! repo_git rev-parse --git-dir > /dev/null 2>&1; then
        echo 0.0.0
        return
    fi
    sha="$(repo_git rev-parse --short=7 HEAD)"
    tag="$(repo_git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2> /dev/null || true)"
    if [[ -n "${tag}" ]]; then
        base="${tag#v}"
        count="$(repo_git rev-list --count "${tag}..HEAD")"
    else
        base=0.0.0
        count="$(repo_git rev-list --count HEAD)"
    fi
    if [[ "${count}" -eq 0 ]]; then
        echo "${base}"
    else
        echo "${base}.git${count}.g${sha}"
    fi
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
