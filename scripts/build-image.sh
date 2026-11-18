#!/usr/bin/env bash
# Turns the rootfs.tar of a variant into what Hekate installs from an SD card:
# the ext4 image (label SWR-DEB) split in parts that fit FAT32, the L4T boot
# files taken from the switch-bsp package, the Hekate ini, and optionally
# Hekate itself. Needs root: the tree is unpacked as it is (ownership, setuid)
# and mke2fs copies it into the image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

VARIANT="xfce"
OUTPUT="${NXD_OUTPUT_DIR}"
SIZE="${NXD_IMAGE_SIZE}"
HEKATE_ZIP=""
NO_HEKATE=0
KEEP_STAGE=0
# Files Hekate asks for in the boot directory; all come from switch-bsp.
BOOT_FILES=(bl31.bin bl33.bin initramfs uImage nx-plat.dtimg)

usage() {
    cat << USAGE
Usage: sudo nxd image [options]

  --variant NAME   variant to package (default: ${VARIANT})
  --output DIR     directory given to nxd rootfs (default: ${OUTPUT})
  --size SIZE      size of the ext4 image, as mke2fs takes it (default: ${SIZE})
  --hekate ZIP     Hekate release to put on the card (default: download the
                   latest one, cached in ${NXD_DOWNLOADS_DIR})
  --no-hekate      do not add Hekate (the card already has it)
  --keep-stage     keep the unpacked tree and the staging directory
  -h, --help       this text

Writes <output>/<variant>/installer.zip and SHA256SUMS next to it. Copy the
contents of the zip to the root of the SD card and use Hekate's partition
manager (Nyx) to flash the l4t.* parts.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:?missing value}"; shift 2 ;;
        --output) OUTPUT="${2:?missing value}"; shift 2 ;;
        --size) SIZE="${2:?missing value}"; shift 2 ;;
        --hekate) HEKATE_ZIP="${2:?missing value}"; shift 2 ;;
        --no-hekate) NO_HEKATE=1; shift ;;
        --keep-stage) KEEP_STAGE=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || die "nxd image needs root (use sudo, or: sudo ./nxd container image ...)"
for tool in mke2fs e2fsck mkimage tar split zip unzip sha256sum; do
    need_cmd "${tool}" "install e2fsprogs, u-boot-tools, zip and unzip"
done
[[ -z "${HEKATE_ZIP}" || -f "${HEKATE_ZIP}" ]] || die "no such file: ${HEKATE_ZIP}"

VARIANT_DIR="${OUTPUT}/${VARIANT}"
TARBALL="${VARIANT_DIR}/rootfs.tar"
[[ -f "${TARBALL}" ]] || die "no rootfs at ${TARBALL} (run: nxd rootfs --variant ${VARIANT})"

NAME="${NXD_BOOT_NAME}"
WORK="${VARIANT_DIR}/image-work"
TREE="${WORK}/tree"
STAGE="${WORK}/stage"
BOOT="${STAGE}/switchroot/${NAME}"
IMG="${WORK}/rootfs.img"

cleanup() {
    if [[ "${KEEP_STAGE}" -eq 0 ]]; then
        rm -rf "${WORK}"
    fi
    hand_back_ownership "${VARIANT_DIR}"
}
trap cleanup EXIT

rm -rf "${WORK}"
mkdir -p "${TREE}" "${BOOT}" "${STAGE}/bootloader/ini" "${STAGE}/switchroot/install"

log "unpacking ${TARBALL}..."
# Only file capabilities are kept as extended attributes: the build host's
# SELinux labels mean nothing on the Switch.
tar -C "${TREE}" --numeric-owner --same-permissions \
    --xattrs --xattrs-include='security.capability' -xf "${TARBALL}"

# --- the boot files ---------------------------------------------------------
BOOTSTACK="${TREE}/opt/switchroot/bootstack"
[[ -d "${BOOTSTACK}" ]] || die "the rootfs has no /opt/switchroot/bootstack: is switch-bsp installed?"
for file in "${BOOT_FILES[@]}" boot.scr; do
    [[ -f "${BOOTSTACK}/${file}" ]] || die "switch-bsp does not ship ${file}"
done
for file in "${BOOT_FILES[@]}"; do
    cp "${BOOTSTACK}/${file}" "${BOOT}/${file}"
done

# boot.scr: a u-boot script image (64-byte header + 8 bytes of sizes) whose text
# sets the kernel command line. Extra arguments go after the cgroup flag, which
# every L4T boot.scr carries.
ANCHOR="systemd.legacy_systemd_cgroup_controller=1"
tail -c +73 "${BOOTSTACK}/boot.scr" > "${WORK}/boot.txt"
if [[ -n "${NXD_KERNEL_CMDLINE_EXTRA}" ]]; then
    grep -q -- "${ANCHOR}" "${WORK}/boot.txt" ||
        die "boot.scr has no '${ANCHOR}' to add '${NXD_KERNEL_CMDLINE_EXTRA}' after (set NXD_KERNEL_CMDLINE_EXTRA= to skip)"
    text="$(cat "${WORK}/boot.txt")"
    printf '%s\n' "${text//"${ANCHOR}"/"${ANCHOR} ${NXD_KERNEL_CMDLINE_EXTRA}"}" > "${WORK}/boot.txt"
fi
mkimage -A arm64 -T script -C none -n boot.scr -d "${WORK}/boot.txt" "${BOOT}/boot.scr" > /dev/null

# Artwork: the repository's own (assets/), else the one of switch-bsp.
pick_asset() {
    local own="$1" fallback="$2" dest="$3"
    if [[ -f "${NXD_ROOT}/assets/${own}" ]]; then
        cp "${NXD_ROOT}/assets/${own}" "${dest}"
    elif [[ -f "${BOOTSTACK}/${fallback}" ]]; then
        cp "${BOOTSTACK}/${fallback}" "${dest}"
    else
        warn "no ${own} and no ${fallback} in switch-bsp: Hekate will show no ${own%%.*}"
    fi
}
pick_asset "bootlogo.bmp" "bootlogo_ubuntu.bmp" "${BOOT}/bootlogo_${NAME}.bmp"
pick_asset "icon.bmp" "icon_ubuntu_hue.bmp" "${BOOT}/icon_${NAME}.bmp"

sed -e "s|@TITLE@|${NXD_BOOT_TITLE}|g" -e "s|@NAME@|${NAME}|g" -e "s|@ID@|${NXD_BOOT_ID}|g" \
    "${NXD_CONFIG_DIR}/boot/hekate.ini" > "${STAGE}/bootloader/ini/${NAME}.ini"

# --- the ext4 image ---------------------------------------------------------
if [[ -z "$(find "${TREE}/usr/lib/firmware/brcm" -name 'brcmfmac4356*' 2> /dev/null | head -n 1)" ]]; then
    warn "no brcmfmac4356 firmware in the rootfs: Wi-Fi will not work"
fi
log "creating the ${SIZE} ext4 image (label ${NXD_BOOT_ID})..."
mke2fs -q -t ext4 -d "${TREE}" -L "${NXD_BOOT_ID}" -b 4096 \
    -O extents,uninit_bg,dir_index -E root_owner=0:0 "${IMG}" "${SIZE}" ||
    die "mke2fs failed: the rootfs probably does not fit in ${SIZE} (try --size)"
e2fsck -fn "${IMG}" > "${WORK}/e2fsck.log" 2>&1 || {
    cat "${WORK}/e2fsck.log" >&2
    die "the filesystem image is not clean"
}

log "splitting it in parts of ${NXD_IMAGE_PART_SIZE} (FAT32 holds less than 4 GiB per file)..."
split -b "${NXD_IMAGE_PART_SIZE}" -d -a 2 "${IMG}" "${STAGE}/switchroot/install/l4t."
rm -f "${IMG}"

# --- Hekate -----------------------------------------------------------------
fetch_hekate() {
    local cache="${NXD_DOWNLOADS_DIR}/hekate_release.zip" url
    if [[ ! -f "${cache}" ]]; then
        need_cmd curl "install curl"
        url="$(curl -fsSL https://api.github.com/repos/CTCaer/hekate/releases/latest |
            grep 'browser_download_url.*hekate_ctcaer.*\.zip' | head -n 1 | cut -d '"' -f 4)" || true
        [[ -n "${url}" ]] || return 1
        mkdir -p "${NXD_DOWNLOADS_DIR}"
        curl -fsSL -o "${cache}" "${url}" || { rm -f "${cache}"; return 1; }
    fi
    printf '%s' "${cache}"
}

if [[ "${NO_HEKATE}" -eq 0 ]]; then
    if [[ -z "${HEKATE_ZIP}" ]]; then
        HEKATE_ZIP="$(fetch_hekate)" || {
            warn "could not download Hekate: the installer will not contain it (use --hekate ZIP)"
            HEKATE_ZIP=""
        }
    fi
    if [[ -n "${HEKATE_ZIP}" ]]; then
        log "adding Hekate from ${HEKATE_ZIP}..."
        unzip -q -o "${HEKATE_ZIP}" -d "${STAGE}"
        # Our ini wins over whatever the release ships under the same name.
        sed -e "s|@TITLE@|${NXD_BOOT_TITLE}|g" -e "s|@NAME@|${NAME}|g" -e "s|@ID@|${NXD_BOOT_ID}|g" \
            "${NXD_CONFIG_DIR}/boot/hekate.ini" > "${STAGE}/bootloader/ini/${NAME}.ini"
    fi
fi

# --- the package ------------------------------------------------------------
ZIP="${VARIANT_DIR}/installer.zip"
rm -f "${ZIP}"
log "packing ${ZIP}..."
(cd "${STAGE}" && zip -q -r -1 "${ZIP}" .)
(cd "${STAGE}/switchroot/install" && sha256sum l4t.* > "${VARIANT_DIR}/SHA256SUMS")
(cd "${VARIANT_DIR}" && sha256sum installer.zip >> SHA256SUMS)

log "installer: ${ZIP}"
log "checksums: ${VARIANT_DIR}/SHA256SUMS"
