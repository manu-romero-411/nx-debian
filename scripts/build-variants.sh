#!/usr/bin/env bash
# Builds the installers: nxd rootfs, nxd inspect and nxd image for one or every
# variant, and gathers what is published (the installers, the package lists,
# the reports and one SHA256SUMS) in a single directory. It is what the CI
# runs, and what to run by hand to get the same files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

VARIANTS=()
OUTPUT="${NXD_OUTPUT_DIR}"
DIST="${NXD_DIST_DIR}"
SKIP_ROOTFS=0
CLEAN=0
ROOTFS_ARGS=()
IMAGE_ARGS=()
# GitHub refuses release assets of 2 GiB or more.
MAX_ASSET_MIB=2000

usage() {
    cat << EOF
Usage: sudo nxd build [options] [-- ROOTFS_OPTIONS]

  --variant NAME   variant to build; repeat it for several (default: all of
                   them: $(list_variants | tr '\n' ' '))
  --all            every variant (the default)
  --output DIR     where the rootfs and the image are made (default: ${OUTPUT})
  --dist DIR       where the files to publish are put (default: ${DIST})
  --size SIZE      size of the ext4 image (default: ${NXD_IMAGE_SIZE})
  --with-hekate    put the latest Hekate in the installers (not by default:
                   whoever installs this already has it); the installer is
                   then named ...-installer-hekate.zip
  --hekate ZIP     put this Hekate release in the installers (implies --with-hekate)
  --require-hekate with --with-hekate: fail when Hekate cannot be downloaded
  --no-hekate      the default: no Hekate
  --skip-rootfs    reuse the rootfs.tar already in --output (only re-image)
  --prereleases    use the newest release of the Retrobox packages even if it
                   is a pre-release (by default, only releases that are not)
  --clean          delete each rootfs.tar once its installer is made (disk)
  -h, --help       this text

Everything after -- goes to nxd rootfs (for example: -- --user manu).

For each variant, <dist> gets:
  ${NXD_DIST_PREFIX}-<variant>-installer.zip (-installer-hekate.zip with Hekate)
  ${NXD_DIST_PREFIX}-<variant>-packages.txt
  ${NXD_DIST_PREFIX}-<variant>-report.txt
and one SHA256SUMS of the lot. Needs root (nxd image does); in a container:
  sudo nxd container build
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANTS+=("${2:?--variant needs a value}"); shift 2 ;;
        --all) VARIANTS=(); shift ;;
        --output) OUTPUT="${2:?--output needs a value}"; shift 2 ;;
        --dist) DIST="${2:?--dist needs a value}"; shift 2 ;;
        --size) IMAGE_ARGS+=(--size "${2:?--size needs a value}"); shift 2 ;;
        --hekate) IMAGE_ARGS+=(--hekate "${2:?--hekate needs a value}"); shift 2 ;;
        --with-hekate) IMAGE_ARGS+=(--with-hekate); shift ;;
        --no-hekate) IMAGE_ARGS+=(--no-hekate); shift ;;
        --require-hekate) IMAGE_ARGS+=(--require-hekate); shift ;;
        --skip-rootfs) SKIP_ROOTFS=1; shift ;;
        --clean) CLEAN=1; shift ;;
        --prereleases) ROOTFS_ARGS+=(--prereleases); shift ;;
        -h | --help) usage; exit 0 ;;
        --) shift; ROOTFS_ARGS+=("$@"); break ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || die "nxd build needs root (use sudo, or: sudo ./nxd container build)"
if [[ ${#VARIANTS[@]} -eq 0 ]]; then
    mapfile -t VARIANTS < <(list_variants)
fi
[[ ${#VARIANTS[@]} -gt 0 ]] || die "there are no variants"
# Fail on a typo before the first (long) build, not after it.
for variant in "${VARIANTS[@]}"; do
    variant_lists "${variant}" > /dev/null
done

mkdir -p "${DIST}"
BUILT=()
for variant in "${VARIANTS[@]}"; do
    log "=== ${variant} ==="
    tarball="${OUTPUT}/${variant}/rootfs.tar"
    if [[ "${SKIP_ROOTFS}" -eq 1 ]]; then
        [[ -f "${tarball}" ]] || die "--skip-rootfs: no ${tarball}"
    else
        "${SCRIPT_DIR}/build-rootfs.sh" --variant "${variant}" --output "${OUTPUT}" "${ROOTFS_ARGS[@]}"
    fi

    # The report is a help, not a gate: it needs python3 and may not read
    # something it did not expect.
    if ! "${SCRIPT_DIR}/inspect-rootfs.sh" --variant "${variant}" --output "${OUTPUT}" > /dev/null; then
        warn "no report for ${variant}"
    fi

    "${SCRIPT_DIR}/build-image.sh" --variant "${variant}" --output "${OUTPUT}" "${IMAGE_ARGS[@]}"

    # the name says what is in the zip (Hekate may have been asked for and not
    # downloaded: --require-hekate is the one that fails then)
    zip="${NXD_DIST_PREFIX}-${variant}-installer.zip"
    if unzip -Z1 "${OUTPUT}/${variant}/installer.zip" | grep -q '^hekate_ctcaer'; then
        zip="${NXD_DIST_PREFIX}-${variant}-installer-hekate.zip"
    fi
    cp "${OUTPUT}/${variant}/installer.zip" "${DIST}/${zip}"
    for pair in manifest.txt:packages.txt report.txt:report.txt; do
        if [[ -f "${OUTPUT}/${variant}/${pair%%:*}" ]]; then
            cp "${OUTPUT}/${variant}/${pair%%:*}" "${DIST}/${NXD_DIST_PREFIX}-${variant}-${pair##*:}"
        fi
    done
    size_mib=$(($(stat -c %s "${DIST}/${zip}") / 1048576))
    if [[ "${size_mib}" -ge "${MAX_ASSET_MIB}" ]]; then
        warn "${zip} is ${size_mib} MiB: GitHub does not take release assets of 2 GiB or more"
    fi
    if [[ "${CLEAN}" -eq 1 ]]; then
        rm -f "${tarball}"
    fi
    BUILT+=("${zip}")
done

sums="$(cd "${DIST}" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum)"
printf '%s\n' "${sums}" > "${DIST}/SHA256SUMS"
hand_back_ownership "${DIST}"
hand_back_ownership "${OUTPUT}"
log "done: ${DIST}"
printf '%s\n' "${BUILT[@]}" >&2
