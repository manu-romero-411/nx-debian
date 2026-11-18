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

usage() {
    cat << EOF
Usage: build-rootfs.sh [options]

  --variant NAME    variant to build (default: ${VARIANT}; see: nxd variants)
  --output DIR      output directory (default: ${NXD_OUTPUT_DIR})
  --format tar|dir  tarball or plain directory (default: ${FORMAT})
  --component NAME  L4T component (default: ${NXD_L4T_COMPONENT})
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
        --dry-run) DRY_RUN=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

case "${FORMAT}" in
    tar | dir) ;;
    *) die "--format must be tar or dir" ;;
esac

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

need_cmd mmdebstrap "apt install mmdebstrap (or use: nxd container rootfs)"
rm -rf "${TARGET}"
mkdir -p "${OUT_DIR}"
log "building ${VARIANT}: ${#PACKAGES[@]} packages, ${NXD_SUITE}/${NXD_ARCH} + L4T ${NXD_L4T_COMPONENT}"
BUILD_LOG="${OUT_DIR}/build.log"
status=0
"${CMD[@]}" > >(tee "${BUILD_LOG}") 2>&1 || status=$?
wait
rm -rf "${STAGE}"
if [[ "${status}" -ne 0 ]]; then
    warn "last lines of the log:"
    tail -n 25 "${BUILD_LOG}" >&2
    die "the build failed (exit ${status}); full log: ${BUILD_LOG}"
fi
log "log: ${BUILD_LOG}"
log "rootfs: ${TARGET}"
log "manifest: ${NXD_MANIFEST}"
