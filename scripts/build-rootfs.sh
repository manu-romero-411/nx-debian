#!/usr/bin/env bash
# Builds the root filesystem of a variant with mmdebstrap: Debian plus the
# L4T repository, every package installed by apt (so dpkg knows all of them,
# and maintainer scripts and SUID bits are the packages' own).
#
# Output: <output dir>/<variant>/rootfs.tar (or rootfs/ with --format dir) and
# manifest.txt, the package list of the result.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

VARIANT="xfce"
FORMAT="tar"
DRY_RUN=0
USER_NAME=""
USER_HASH=""
NO_PASSWORD=0
NO_USER=0
NO_RELEASES=0
RELEASES_DIR=""

usage() {
    cat << EOF
Usage: build-rootfs.sh [options]

  --variant NAME    variant to build (default: ${VARIANT}; see: nxd variants)
  --output DIR      output directory (default: ${NXD_OUTPUT_DIR})
  --format tar|dir  tarball or plain directory (default: ${FORMAT})
  --component NAME  L4T component (default: ${NXD_L4T_COMPONENT})
  --user NAME       create this user (uid 1000) in the image; the password comes
                    from --password-hash, from \$NXD_PASSWORD or from a prompt
  --password-hash H crypt(3) hash of the password (openssl passwd -6)
  --no-password     with --user: leave the account without a password
  --no-user         no user, even when the variant has a default one
  --no-releases     skip the release packages the variant installs (offline)
  --releases-dir D  use the .deb files in D instead of downloading the releases
  --dry-run         print the mmdebstrap command and stop
  -h, --help        this text

Needs root, or a kernel that lets mmdebstrap use user namespaces.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:?--variant needs a value}"; shift 2 ;;
        --output) NXD_OUTPUT_DIR="${2:?--output needs a value}"; shift 2 ;;
        --format) FORMAT="${2:?--format needs a value}"; shift 2 ;;
        --component) NXD_L4T_COMPONENT="${2:?--component needs a value}"; shift 2 ;;
        --user) USER_NAME="${2:?--user needs a value}"; shift 2 ;;
        --password-hash) USER_HASH="${2:?--password-hash needs a value}"; shift 2 ;;
        --no-password) NO_PASSWORD=1; shift ;;
        --no-user) NO_USER=1; shift ;;
        --no-releases) NO_RELEASES=1; shift ;;
        --releases-dir) RELEASES_DIR="${2:?--releases-dir needs a value}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

case "${FORMAT}" in
    tar | dir) ;;
    *) die "--format must be tar or dir" ;;
esac

# A variant can ship a default user (a public account of a console image):
# --user replaces it, --no-user drops it, $NXD_PASSWORD overrides its password.
if [[ -z "${USER_NAME}" && "${NO_USER}" -eq 0 ]]; then
    USER_NAME="$(variant_setting "${VARIANT}" NXD_DEFAULT_USER)"
    if [[ -n "${USER_NAME}" && -z "${USER_HASH}" ]]; then
        NXD_PASSWORD="${NXD_PASSWORD:-$(variant_setting "${VARIANT}" NXD_DEFAULT_PASSWORD)}"
        [[ -n "${NXD_PASSWORD}" ]] || NO_PASSWORD=1
    fi
fi
if [[ -n "${USER_NAME}" ]]; then
    [[ "${USER_NAME}" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] ||
        die "--user: '${USER_NAME}' is not a valid login name"
    if [[ -z "${USER_HASH}" && "${NO_PASSWORD}" -eq 0 ]]; then
        if [[ -z "${NXD_PASSWORD:-}" && "${DRY_RUN}" -eq 0 ]]; then
            [[ -t 0 ]] || die "--user needs a password: set NXD_PASSWORD, pass --password-hash or --no-password"
            read -rsp "Password for ${USER_NAME}: " NXD_PASSWORD
            printf '\n'
            read -rsp "Again: " again
            printf '\n'
            [[ "${NXD_PASSWORD}" == "${again}" ]] || die "the passwords differ"
        fi
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            USER_HASH="(hash)"
        else
            need_cmd openssl "install openssl"
            USER_HASH="$(printf '%s' "${NXD_PASSWORD}" | openssl passwd -6 -stdin)"
        fi
    fi
elif [[ -n "${USER_HASH}" || "${NO_PASSWORD}" -eq 1 ]]; then
    die "--password-hash and --no-password need --user"
fi

verify_key "${NXD_L4T_KEY}" "${NXD_L4T_KEY_FPR}"
mapfile -t PACKAGES < <(variant_packages "${VARIANT}")
[[ ${#PACKAGES[@]} -gt 0 ]] || die "variant '${VARIANT}' has no packages"

OUT_DIR="${NXD_OUTPUT_DIR}/${VARIANT}"
if [[ "${FORMAT}" == "tar" ]]; then
    TARGET="${OUT_DIR}/rootfs.tar"
else
    TARGET="${OUT_DIR}/rootfs"
fi
export NXD_MANIFEST="${OUT_DIR}/manifest.txt"

# What goes into the rootfs besides the packages: the L4T key, source and pins
# (they stay in the image, so apt keeps working with both repositories after
# the first boot), the package list and the hooks of config/hooks.
STAGE="${OUT_DIR}/stage"
KEY_NAME="$(basename "${NXD_L4T_KEY}")"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp "${NXD_L4T_KEY}" "${STAGE}/${KEY_NAME}"
{
    render_compat_pins
    printf '\n'
    render_pins "$(url_host "${NXD_L4T_URL}")"
} > "${STAGE}/10-nxd-l4t.pref"
compat_sources_file "${NXD_ARCH}" > "${STAGE}/nxd-compat.sources"
l4t_sources_file "${NXD_ARCH}" "/etc/apt/keyrings/${KEY_NAME}" "${NXD_L4T_COMPONENT}" \
    > "${STAGE}/nxd-l4t.sources"
printf '%s\n' "${PACKAGES[@]}" > "${STAGE}/nxd-packages"
dpkg_excludes_file "${VARIANT}" > "${STAGE}/nxd-excludes"
# One unit name per line, for config/hooks/30-services.sh.
variant_setting "${VARIANT}" NXD_MASK_UNITS | tr -s '[:space:]' '\n' | sed '/^$/d' > "${STAGE}/nxd-mask"
variant_setting "${VARIANT}" NXD_DISABLE_UNITS | tr -s '[:space:]' '\n' | sed '/^$/d' > "${STAGE}/nxd-disable"

# The packages of the variant that come from GitHub releases, not from apt.
# Before anything is downloaded: no point in fetching packages for a build
# that cannot run.
if [[ "${DRY_RUN}" -eq 0 ]]; then
    need_cmd mmdebstrap "apt install mmdebstrap, or run it in a container: sudo ./nxd container build"
fi
RELEASE_LIST="$(variant_setting "${VARIANT}" NXD_RELEASE_LIST)"
HAVE_DEBS=0
if [[ -n "${RELEASE_LIST}" && "${NO_RELEASES}" -eq 0 ]]; then
    HAVE_DEBS=1
    if [[ -n "${RELEASES_DIR}" ]]; then
        [[ -d "${RELEASES_DIR}" ]] || die "no such directory: ${RELEASES_DIR}"
        compgen -G "${RELEASES_DIR}/*.deb" > /dev/null || die "no .deb files in ${RELEASES_DIR}"
        mkdir -p "${STAGE}/nxd-debs"
        cp "${RELEASES_DIR}"/*.deb "${STAGE}/nxd-debs/"
        chmod 644 "${STAGE}/nxd-debs"/*.deb
    elif [[ "${DRY_RUN}" -eq 0 ]]; then
        "${SCRIPT_DIR}/fetch-releases.sh" "${RELEASE_LIST}" "${STAGE}/nxd-debs"
    fi
fi
if [[ -n "${USER_NAME}" ]]; then
    (umask 077; printf '%s\n%s\n%s\n' "${USER_NAME}" "${USER_HASH}" \
        "$(variant_setting "${VARIANT}" NXD_AUTOLOGIN_SESSION)" > "${STAGE}/nxd-user")
fi

# add_hooks DIR: run every DIR/*.sh inside the rootfs, in name order.
add_hooks() {
    local hook base
    for hook in "$1"/*.sh; do
        [[ -f "${hook}" ]] || continue
        base="$(basename "${hook}")"
        CMD+=(
            --customize-hook="copy-in ${hook} /tmp"
            --customize-hook="chroot \"\$1\" sh /tmp/${base}"
            --customize-hook="rm -f \"\$1/tmp/${base}\""
        )
    done
}

# Two phases. mmdebstrap only bootstraps Debian (minbase plus apt and the certificates
# needed for https). The L4T repository is then added and everything is
# installed by apt *inside* the rootfs: the same apt, with the same pins, as
# the one the console will run, and no key path has to make sense on the host
# (during the bootstrap apt runs on the host side, where /etc/apt/keyrings of
# the target does not exist).
#
# The $1 in the hooks is expanded by mmdebstrap's shell (the rootfs path),
# not by this script: hence the single quotes.
# shellcheck disable=SC2016
CMD=(
    mmdebstrap
    --variant=minbase
    --architectures="${NXD_ARCH}"
    --components="${NXD_COMPONENTS}"
    --aptopt='APT::Install-Recommends "false"'
    --include="${NXD_BOOTSTRAP_PACKAGES// /,}"
    --customize-hook='mkdir -p "$1/etc/apt/keyrings" "$1/etc/apt/preferences.d" "$1/etc/apt/sources.list.d"'
    --customize-hook="copy-in ${STAGE}/${KEY_NAME} /etc/apt/keyrings"
    --customize-hook="copy-in ${STAGE}/10-nxd-l4t.pref /etc/apt/preferences.d"
    --customize-hook="copy-in ${STAGE}/nxd-l4t.sources /etc/apt/sources.list.d"
)
if [[ -s "${STAGE}/nxd-compat.sources" ]]; then
    CMD+=(--customize-hook="copy-in ${STAGE}/nxd-compat.sources /etc/apt/sources.list.d")
fi
if [[ -s "${STAGE}/nxd-excludes" ]]; then
    # The bootstrap (apt and the essential set) goes in before any hook can
    # write a dpkg config file, so it gets the excludes as options; the file
    # stays in the image for what is installed later with apt.
    while IFS= read -r line; do
        [[ "${line}" == path-* ]] && CMD+=("--dpkgopt=${line}")
    done < "${STAGE}/nxd-excludes"
    CMD+=(--customize-hook="copy-in ${STAGE}/nxd-excludes /etc/dpkg/dpkg.cfg.d")
fi
# shellcheck disable=SC2016
CMD+=(
    --customize-hook="copy-in ${STAGE}/nxd-packages /tmp"
    --customize-hook='chroot "$1" apt-get update'
)
add_hooks "${NXD_CONFIG_DIR}/pre-hooks"
# shellcheck disable=SC2016
CMD+=(
    --customize-hook='chroot "$1" env DEBIAN_FRONTEND=noninteractive sh -c "apt-get install -y --no-install-recommends \$(cat /tmp/nxd-packages)"'
    --customize-hook='rm -f "$1/tmp/nxd-packages"'
)
# Static files of the repository (hostname, fstab...): config/overlay/common,
# then config/overlay/<variant>, each top-level entry copied into /.
for overlay in "${NXD_CONFIG_DIR}/overlay/common" "${NXD_CONFIG_DIR}/overlay/${VARIANT}"; do
    [[ -d "${overlay}" ]] || continue
    for entry in "${overlay}"/*; do
        [[ -e "${entry}" ]] && CMD+=(--customize-hook="copy-in ${entry} /")
    done
done
if [[ "${HAVE_DEBS}" -eq 1 ]]; then
    # shellcheck disable=SC2016
    CMD+=(
        --customize-hook="copy-in ${STAGE}/nxd-debs /tmp"
        --customize-hook='chroot "$1" env DEBIAN_FRONTEND=noninteractive sh -c "apt-get install -y --no-install-recommends /tmp/nxd-debs/*.deb"'
        --customize-hook='rm -rf "$1/tmp/nxd-debs"'
    )
fi
if [[ -s "${STAGE}/nxd-mask" ]]; then
    CMD+=(--customize-hook="copy-in ${STAGE}/nxd-mask /tmp")
fi
if [[ -s "${STAGE}/nxd-disable" ]]; then
    CMD+=(--customize-hook="copy-in ${STAGE}/nxd-disable /tmp")
fi
if [[ -s "${STAGE}/nxd-user" ]]; then
    CMD+=(--customize-hook="copy-in ${STAGE}/nxd-user /tmp")
fi
add_hooks "${NXD_CONFIG_DIR}/hooks"
# shellcheck disable=SC2016
CMD+=(
    --customize-hook='chroot "$1" dpkg-query -W -f "\${binary:Package}\t\${Version}\n" > "$NXD_MANIFEST"'
    --customize-hook='chroot "$1" apt-get clean'
    "${NXD_SUITE}"
    "${TARGET}"
    "deb ${NXD_MIRROR} ${NXD_SUITE} ${NXD_COMPONENTS}"
)

if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '%q ' "${CMD[@]}"
    printf '\n'
    exit 0
fi

rm -rf "${TARGET}"
mkdir -p "${OUT_DIR}"
log "building ${VARIANT}: ${#PACKAGES[@]} packages, ${NXD_SUITE}/${NXD_ARCH} + L4T ${NXD_L4T_COMPONENT}"
BUILD_LOG="${OUT_DIR}/build.log"
status=0
"${CMD[@]}" > >(tee "${BUILD_LOG}") 2>&1 || status=$?
wait
rm -rf "${STAGE}"
# Built as root (sudo, or a container): hand the output back to whoever owns
# the directory it lives in, so it can be read and written without sudo.
hand_back_ownership "${NXD_OUTPUT_DIR}"
if [[ "${status}" -ne 0 ]]; then
    warn "last lines of the log:"
    tail -n 25 "${BUILD_LOG}" >&2
    die "the build failed (exit ${status}); full log: ${BUILD_LOG}"
fi
log "log: ${BUILD_LOG}"
log "rootfs: ${TARGET}"
log "manifest: ${NXD_MANIFEST}"
