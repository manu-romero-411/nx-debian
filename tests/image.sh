#!/usr/bin/env bash
# Test of `nxd image` on a hand-made rootfs.tar: no network, no mmdebstrap,
# but root, e2fsprogs, u-boot-tools and zip.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
NXD="${NXD_ROOT}/nxd"

if [[ "${EUID}" -ne 0 ]]; then
    echo "skipped: nxd image needs root"
    exit 0
fi
for tool in mke2fs mkimage zip unzip debugfs dumpe2fs; do
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
trap 'rm -rf "${tmp}"' EXIT

# A rootfs with what the image needs from switch-bsp.
tree="${tmp}/tree"
bootstack="${tree}/opt/switchroot/bootstack"
mkdir -p "${bootstack}" "${tree}/usr/bin" "${tree}/home/manu" "${tree}/usr/lib/firmware/brcm" "${tree}/etc"
for file in bl31.bin bl33.bin initramfs uImage nx-plat.dtimg bootlogo_ubuntu.bmp icon_ubuntu_hue.bmp; do
    printf '%s\n' "${file}" > "${bootstack}/${file}"
done
printf 'setenv bootargs "root=/dev/mmcblk0p2 systemd.legacy_systemd_cgroup_controller=1 quiet"\n' > "${tmp}/boot.txt"
mkimage -A arm64 -T script -C none -n boot.scr -d "${tmp}/boot.txt" "${bootstack}/boot.scr" > /dev/null
printf 'LABEL=NXDEB / ext4 noatime 0 1\n' > "${tree}/etc/fstab"
: > "${tree}/usr/bin/sudo"
chmod 4755 "${tree}/usr/bin/sudo"
: > "${tree}/home/manu/file"
chown -R 1000:1000 "${tree}/home/manu"
: > "${tree}/usr/lib/firmware/brcm/brcmfmac4356A3-pcie.bin"
head -c 20000000 /dev/urandom > "${tree}/etc/random.bin"
OUT="${tmp}/out"
mkdir -p "${OUT}/fake"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .

export NXD_IMAGE_PART_SIZE=16M
"${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 40M > "${tmp}/image.log" 2>&1 ||
    { cat "${tmp}/image.log"; bad "the image was built"; }
INSTALLER="${OUT}/fake/installer.zip"
check "the installer exists" test -f "${INSTALLER}"
LIST="$(unzip -Z1 "${INSTALLER}" 2> /dev/null || true)"
check "the image is split in parts" grep -q 'switchroot/install/l4t.01' <<< "${LIST}"
check "the boot files are in the zip" grep -q 'switchroot/debian/uImage' <<< "${LIST}"
check "the ini is in the zip" grep -q 'bootloader/ini/debian.ini' <<< "${LIST}"
check "the artwork is renamed" grep -q 'switchroot/debian/bootlogo_debian.bmp' <<< "${LIST}"

INI="$(unzip -p "${INSTALLER}" bootloader/ini/debian.ini)"
check "the ini names the boot directory" grep -q 'boot_prefixes=/switchroot/debian/' <<< "${INI}"
check "the ini carries the id" grep -q '^id=NXDEB' <<< "${INI}"
check "rebooting goes back to hekate" grep -qx 'r2p_action=bootloader' <<< "${INI}"
check "the boot is quiet" grep -q '^bootargs_extra=quiet ' <<< "${INI}"
check "boot.scr got the extra argument" \
    grep -q 'legacy_systemd_cgroup_controller=1 net.ifnames=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1' \
    <(unzip -p "${INSTALLER}" switchroot/debian/boot.scr | tail -c +73)

# Another boot id: label and fstab follow it.
NXD_BOOT_ID=SWR-OTHER "${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 40M > /dev/null 2>&1
unzip -q -o "${INSTALLER}" -d "${tmp}/o"
cat "${tmp}/o"/switchroot/install/l4t.* > "${tmp}/other.img"
check "the label follows the boot id" grep -q 'Filesystem volume name: *SWR-OTHER' <(dumpe2fs -h "${tmp}/other.img" 2> /dev/null)
"${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 40M > /dev/null 2>&1

# Put the parts together again and look inside.
mkdir "${tmp}/x"
unzip -q "${INSTALLER}" -d "${tmp}/x"
cat "${tmp}/x"/switchroot/install/l4t.* > "${tmp}/joined.img"
check "the label is NXDEB" grep -q 'Filesystem volume name: *NXDEB' <(dumpe2fs -h "${tmp}/joined.img" 2> /dev/null)
check "the owner of the user files is kept" grep -q 'User: *1000 *Group: *1000' <(debugfs -R 'stat /home/manu/file' "${tmp}/joined.img" 2> /dev/null)
check "setuid is kept" grep -q 'Mode: *0*4755' <(debugfs -R 'stat /usr/bin/sudo' "${tmp}/joined.img" 2> /dev/null)
check "root is owned by root" grep -q 'User: *0 *Group: *0' <(debugfs -R 'stat /' "${tmp}/joined.img" 2> /dev/null)

check "fstab follows the boot id" grep -q 'LABEL=SWR-OTHER' \
    <(debugfs -R 'cat /etc/fstab' "${tmp}/other.img" 2> /dev/null)
check "the checksums list the parts and the zip" test "$(wc -l < "${OUT}/fake/SHA256SUMS")" -ge 3
check "the zip checksum is right" bash -c "cd '${OUT}/fake' && grep installer.zip SHA256SUMS | sha256sum -c -"
check "the work directory is gone" test ! -d "${OUT}/fake/image-work"

# nxd build: the files to publish, from the rootfs that is already there.
CONFIG="${tmp}/config"
cp -r "${NXD_ROOT}/config" "${CONFIG}"
printf 'NXD_VARIANT_DESCRIPTION="fake"\nNXD_VARIANT_LISTS="base"\n' > "${CONFIG}/variants/fake.conf"
DIST="${tmp}/dist"
NXD_CONFIG_DIR="${CONFIG}" NXD_DIST_PREFIX=test-prefix "${NXD}" build --variant fake --skip-rootfs --no-hekate \
    --size 40M --output "${OUT}" --dist "${DIST}" --clean > "${tmp}/build.log" 2>&1 ||
    { cat "${tmp}/build.log"; bad "nxd build ran"; }
check "build names the installer after the prefix and the variant" test -f "${DIST}/test-prefix-fake-installer.zip"
check "build gives the installer the same content" cmp -s "${DIST}/test-prefix-fake-installer.zip" "${OUT}/fake/installer.zip"
check "build writes one SHA256SUMS of the lot" bash -c "cd '${DIST}' && sha256sum -c SHA256SUMS"
check "build does not checksum its own list" test "$(grep -c SHA256SUMS "${DIST}/SHA256SUMS" || true)" -eq 0
check "--clean removes the rootfs.tar" test ! -f "${OUT}/fake/rootfs.tar"
check_not "build refuses a variant that does not exist" \
    env NXD_CONFIG_DIR="${CONFIG}" "${NXD}" build --variant nope --skip-rootfs --output "${OUT}" --dist "${DIST}"
check_not "--skip-rootfs without a rootfs is refused" \
    env NXD_CONFIG_DIR="${CONFIG}" "${NXD}" build --variant fake --skip-rootfs --output "${OUT}" --dist "${DIST}"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .

# Failures that must be reported, not built around
printf 'setenv bootargs "root=/dev/mmcblk0p2 quiet"\n' > "${tmp}/boot.txt"
mkimage -A arm64 -T script -C none -n boot.scr -d "${tmp}/boot.txt" "${bootstack}/boot.scr" > /dev/null
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
check_not "a boot.scr without the anchor is refused" \
    "${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 40M
check "an empty extra command line skips the anchor" \
    env NXD_KERNEL_CMDLINE_EXTRA= "${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 40M
check_not "an image too small is refused" "${NXD}" image --variant fake --output "${OUT}" --no-hekate --size 8M
check_not "--require-hekate fails when Hekate cannot be fetched" \
    env NXD_KERNEL_CMDLINE_EXTRA= NXD_GITHUB_API=http://127.0.0.1:9 NXD_DOWNLOADS_DIR="${tmp}/empty-downloads" \
    "${NXD}" image --variant fake --output "${OUT}" --require-hekate --size 40M
check "with --with-hekate alone it only warns" \
    env NXD_KERNEL_CMDLINE_EXTRA= NXD_GITHUB_API=http://127.0.0.1:9 NXD_DOWNLOADS_DIR="${tmp}/empty-downloads" \
    "${NXD}" image --variant fake --output "${OUT}" --with-hekate --size 40M

# Hekate is optional: not in the installer unless it is asked for.
export NXD_KERNEL_CMDLINE_EXTRA= # this boot.scr has no anchor to add to
mkdir -p "${tmp}/hekate/bootloader/res"
: > "${tmp}/hekate/hekate_ctcaer_6.0.0_Nyx_1.0.0.bin"
: > "${tmp}/hekate/bootloader/res/icon.bmp"
(cd "${tmp}/hekate" && zip -q -r "${tmp}/hekate-fake.zip" .)
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
env NXD_KERNEL_CMDLINE_EXTRA= NXD_GITHUB_API=http://127.0.0.1:9 NXD_DOWNLOADS_DIR="${tmp}/empty-downloads" \
    "${NXD}" image --variant fake --output "${OUT}" --size 40M > /dev/null 2>&1 || bad "image without options ran"
check "by default Hekate is not in the installer" bash -c "! unzip -Z1 '${OUT}/fake/installer.zip' | grep -q '^hekate_ctcaer'"
check "by default nothing is downloaded (no warning about Hekate)" bash -c "
    env NXD_KERNEL_CMDLINE_EXTRA= NXD_GITHUB_API=http://127.0.0.1:9 NXD_DOWNLOADS_DIR='${tmp}/empty-downloads' \
    '${NXD}' image --variant fake --output '${OUT}' --size 40M 2>&1 | grep -qi 'hekate' && exit 1 || exit 0"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
"${NXD}" image --variant fake --output "${OUT}" --hekate "${tmp}/hekate-fake.zip" --size 40M > "${tmp}/h.log" 2>&1 || { cat "${tmp}/h.log"; bad "image --hekate ran"; }
check "--hekate ZIP puts Hekate in the installer" bash -c "unzip -Z1 '${OUT}/fake/installer.zip' | grep -q '^hekate_ctcaer_6.0.0'"
check "...with our ini next to it" bash -c "unzip -Z1 '${OUT}/fake/installer.zip' | grep -q '^bootloader/ini/'"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
check "--no-hekate wins over --hekate ZIP" bash -c "'${NXD}' image --variant fake --output '${OUT}' --hekate '${tmp}/hekate-fake.zip' --no-hekate --size 40M > /dev/null 2>&1 && ! unzip -Z1 '${OUT}/fake/installer.zip' | grep -q '^hekate_ctcaer'"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
DIST2="${tmp}/dist2"
NXD_CONFIG_DIR="${CONFIG}" NXD_DIST_PREFIX=test-prefix "${NXD}" build --variant fake --skip-rootfs --hekate "${tmp}/hekate-fake.zip" \
    --size 40M --output "${OUT}" --dist "${DIST2}" > /dev/null 2>&1 || bad "nxd build --hekate ran"
check "build names an installer with Hekate ...-installer-hekate.zip" test -f "${DIST2}/test-prefix-fake-installer-hekate.zip"
check "...and not the plain name" test ! -f "${DIST2}/test-prefix-fake-installer.zip"
tar -C "${tree}" --numeric-owner -cf "${OUT}/fake/rootfs.tar" .
check_not "a missing rootfs is refused" "${NXD}" image --variant nope --output "${OUT}" --no-hekate

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
