#!/usr/bin/env bash
# Integration test of `nxd spike` and `nxd rootfs` against a fake L4T
# repository, so the machinery can be tested without the real one.
#
# It needs root, network (an Ubuntu archive), mmdebstrap, dpkg-dev and gnupg.
# Ubuntu noble / amd64 stands in for Debian trixie / arm64: the mechanics
# (apt, pins, hooks, the L4T source and key) are the same, the package names
# the real build needs are not tested here.
#
# The fake repository has two components, like the real one:
#   jammy: nvidia-l4t-core needs a library nobody has      -> must be reported
#   noble: nvidia-l4t-core needs a library noble has       -> must resolve
# plus a "xserver-xorg-core" older than the suite's, which only the pin keeps.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
NXD="${NXD_ROOT}/nxd"
MIRROR="${NXD_TEST_MIRROR:-http://archive.ubuntu.com/ubuntu}"
KEYRING="${NXD_TEST_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}"

[[ "$(id -u)" -eq 0 ]] || {
    echo "needs root (mmdebstrap)" >&2
    exit 1
}
for cmd in mmdebstrap dpkg-scanpackages dpkg-deb apt-ftparchive gpg; do
    command -v "${cmd}" > /dev/null || {
        echo "missing ${cmd}" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
}
# expect DESCRIPTION TEXT PATTERN: TEXT must match the extended regex.
expect() {
    if grep -Eq -- "$3" <<< "$2"; then
        ok "$1"
    else
        bad "$1"
    fi
}

# --- a signing key and the fake repository -------------------------------
export GNUPGHOME="${WORK}/gnupg"
mkdir -m 700 "${GNUPGHOME}"
gpg --batch --quiet --passphrase '' --quick-generate-key "nxd test <test@invalid>" rsa2048 sign never
KEY_FPR="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"

# mkpkg POOLDIR NAME VERSION DEPENDS [FILE [PREINST]]: a one-file package.
mkpkg() {
    local pool="$1" name="$2" version="$3" depends="$4" file="${5:-}" preinst="${6:-}" tree
    tree="$(mktemp -d "${WORK}/pkg.XXXXXX")"
    mkdir -p "${tree}/DEBIAN"
    {
        printf 'Package: %s\nVersion: %s\nArchitecture: amd64\n' "${name}" "${version}"
        printf 'Maintainer: test <test@invalid>\nDescription: nxd test package\n'
        if [[ -n "${depends}" ]]; then
            printf 'Depends: %s\n' "${depends}"
        fi
    } > "${tree}/DEBIAN/control"
    if [[ -n "${file}" ]]; then
        mkdir -p "${tree}/$(dirname "${file}")"
        printf '#!/bin/sh\n' > "${tree}/${file}"
        chmod 755 "${tree}/${file}"
    fi
    if [[ -n "${preinst}" ]]; then
        printf '#!/bin/sh\n%s\n' "${preinst}" > "${tree}/DEBIAN/preinst"
        chmod 755 "${tree}/DEBIAN/preinst"
    fi
    mkdir -p "${pool}"
    dpkg-deb --build "${tree}" "${pool}/${name}_${version}_amd64.deb" > /dev/null
}

REPO="${WORK}/repo"
for component in jammy noble; do
    if [[ "${component}" == "jammy" ]]; then
        core_dep="libnonexistent-l4t0"
    else
        core_dep="libpng16-16t64"
    fi
    # Like nvidia-l4t-ccp-*: refuses to install without NVIDIA's flag file.
    mkpkg "${REPO}/pool/${component}" nvidia-l4t-core "1.0~${component}" "${core_dep}" usr/sbin/nvpmodel \
        'test -f /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall || { echo "Unknown Tegra platform"; exit 1; }'
    # libicu70 only exists in Ubuntu jammy: the compat suite has to provide it.
    if [[ "${component}" == "noble" ]]; then
        bsp_dep="libicu70"
    else
        bsp_dep=""
    fi
    # Like switch-bsp: wants to mount the boot partition unless told otherwise.
    mkpkg "${REPO}/pool/${component}" switch-bsp "1.0~${component}" "${bsp_dep}" "" \
        'test -f /opt/switchroot/image_prep || { echo "Mounting boot disk"; exit 32; }'
    mkpkg "${REPO}/pool/${component}" xserver-xorg-core "2:1.20.13-fake1" ""
    mkdir -p "${REPO}/dists/l4t/${component}/binary-amd64"
    (cd "${REPO}" && dpkg-scanpackages --arch amd64 "pool/${component}" \
        > "dists/l4t/${component}/binary-amd64/Packages" 2> /dev/null)
done
apt-ftparchive \
    -o APT::FTPArchive::Release::Suite=l4t -o APT::FTPArchive::Release::Codename=l4t \
    -o APT::FTPArchive::Release::Components="jammy noble" \
    -o APT::FTPArchive::Release::Architectures=amd64 \
    release "${REPO}/dists/l4t" > "${REPO}/dists/l4t/Release"
gpg --batch --quiet --clearsign -o "${REPO}/dists/l4t/InRelease" "${REPO}/dists/l4t/Release"
gpg --batch --quiet --armor --export "${KEY_FPR}" > "${WORK}/test-L4T.asc"

# --- a config for the test -------------------------------------------------
CONFIG="${WORK}/config"
cp -r "${NXD_ROOT}/config" "${CONFIG}"
rm -f "${CONFIG}/keys/"*
cp "${WORK}/test-L4T.asc" "${CONFIG}/keys/test-L4T.asc"
printf 'ca-certificates\n' > "${CONFIG}/packages/base.list"
printf 'nvidia-l4t-core\nswitch-bsp\nxserver-xorg-core\n' > "${CONFIG}/packages/l4t.list"
printf '# nothing\n' > "${CONFIG}/packages/x11.list"
# Stands for lightdm: all the user hook looks for is /etc/lightdm.
mkdir -p "${CONFIG}/overlay/test/etc/lightdm"
: > "${CONFIG}/overlay/test/etc/lightdm/.keep"
printf 'NXD_VARIANT_DESCRIPTION="test"\nNXD_VARIANT_LISTS="base l4t x11"\nNXD_PATH_EXCLUDES="/usr/share/doc/* /usr/share/man/*"\nNXD_PATH_INCLUDES="/usr/share/doc/*/copyright"\nNXD_MASK_UNITS="apt-daily.timer fstrim.timer"\nNXD_AUTOLOGIN_SESSION="xfce"\nNXD_RELEASE_LIST="test"\n' > "${CONFIG}/variants/test.conf"
# A release package, as --releases-dir hands it over (no network needed).
mkdir -p "${WORK}/release-pkg/DEBIAN" "${WORK}/release-pkg/opt/fake" "${WORK}/releases"
printf 'Package: fake-release\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@invalid>\nDescription: t\n' > "${WORK}/release-pkg/DEBIAN/control"
printf 'hello\n' > "${WORK}/release-pkg/opt/fake/hello"
dpkg-deb --build "${WORK}/release-pkg" "${WORK}/releases/fake-release_1.0_all.deb" > /dev/null

# A hook of this variant only (config/hooks/<variant>/), and one of another
# variant that must not run.
mkdir -p "${CONFIG}/hooks/test" "${CONFIG}/hooks/other"
printf '#!/bin/sh\ntouch /nxd-variant-hook\n' > "${CONFIG}/hooks/test/10-marker.sh"
printf '#!/bin/sh\ntouch /nxd-other-hook\n' > "${CONFIG}/hooks/other/10-marker.sh"

export NXD_CONFIG_DIR="${CONFIG}"
export NXD_L4T_KEY="${CONFIG}/keys/test-L4T.asc"
export NXD_L4T_KEY_FPR="${KEY_FPR}"
export NXD_L4T_URL="file://${REPO}"
export NXD_ARCH=amd64
export NXD_SUITE=noble
export NXD_MIRROR="${MIRROR}"
export NXD_COMPONENTS="main universe"
export NXD_COMPAT_SUITE=jammy
export NXD_COMPAT_PACKAGES=libicu70
export NXD_BOOTSTRAP_PACKAGES="apt ca-certificates ubuntu-keyring"

# --- the spike -----------------------------------------------------------------
REPORT="${WORK}/report.md"
"${NXD}" spike --variant test --components "jammy noble" --keyring "${KEYRING}" \
    --contents --report "${REPORT}" > "${WORK}/spike.out" 2>&1 || {
    cat "${WORK}/spike.out"
    bad "the spike ran"
}
SPIKE_OUT="$(cat "${WORK}/spike.out")"

# section NAME: the report from "## NAME" to the next "## ".
section() {
    awk -v name="$1" '/^## / { f = (index($0, "## " name) == 1) } f' "${REPORT}"
}

expect "spike: the Debian side resolves" "${SPIKE_OUT}" '^debian +OK'
expect "spike: a missing library is reported (jammy)" "${SPIKE_OUT}" '^l4t-jammy-nopin +UNMET DEPENDENCIES'
expect "spike: the jammy report names the library" "$(section l4t-jammy-nopin)" 'libnonexistent-l4t0'
expect "spike: noble resolves without pins" "${SPIKE_OUT}" '^l4t-noble-nopin +OK'
expect "spike: noble resolves with pins" "${SPIKE_OUT}" '^l4t-noble-pin +OK'
expect "spike: without the pin the suite's Xorg wins" "$(section l4t-noble-nopin)" \
    'xserver-xorg-core +2:21\.[0-9.]+.* 500 '
expect "spike: with the pin the L4T Xorg wins" "$(section l4t-noble-pin)" \
    'xserver-xorg-core +2:1\.20\.13-fake1 +1001 '
expect "spike: --contents finds nvpmodel" "$(cat "${REPORT}")" 'nvidia-l4t-core: .*/usr/sbin/nvpmodel'
expect "spike: the compat suite provides the dropped library" "$(section l4t-noble-pin)" \
    'libicu70 +[0-9][^ ]* +100 .*jammy'
expect "spike: the extras table is there" "$(cat "${REPORT}")" 'xfce4-volumed-pulse'

# --- the rootfs -------------------------------------------------------------------
# apt runs inside the rootfs, which cannot see file:// paths of the host: serve
# the repository over http on the loopback interface.
PORT=18080
python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${REPO}" > "${WORK}/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill "${HTTP_PID}" 2> /dev/null || true; rm -rf "${WORK}"' EXIT
sleep 1
export NXD_L4T_URL="http://127.0.0.1:${PORT}/"
OUT="${WORK}/out"
NXD_PASSWORD='s3cret' "${NXD}" rootfs --variant test --component noble --user manu --releases-dir "${WORK}/releases" --output "${OUT}" > "${WORK}/rootfs.out" 2>&1 || {
    tail -n 30 "${WORK}/rootfs.out"
    bad "the rootfs was built"
}
TAR="${OUT}/test/rootfs.tar"
if [[ -f "${TAR}" ]]; then
    ok "rootfs: the tarball exists"
    LISTING="$(tar -tvf "${TAR}")"
    expect "rootfs: the L4T key is in the image" "${LISTING}" 'etc/apt/keyrings/test-L4T\.asc'
    expect "rootfs: the pins are in the image" "${LISTING}" 'etc/apt/preferences\.d/10-nxd-l4t\.pref'
    expect "rootfs: firstboot is masked" "${LISTING}" 'systemd-firstboot\.service -> /dev/null'
    expect "rootfs: the machine-id is empty" "$(tar -tvf "${TAR}" ./etc/machine-id)" ' 0 [0-9-]+ [0-9:]+ \./etc/machine-id'
    expect "rootfs: the L4T source is kept, with its key" \
        "$(tar -xOf "${TAR}" ./etc/apt/sources.list.d/nxd-l4t.sources 2> /dev/null || true)" \
        'Signed-By: /etc/apt/keyrings/test-L4T\.asc'
    MANIFEST="$(cat "${OUT}/test/manifest.txt")"
    expect "rootfs: the pinned Xorg is the one installed" "${MANIFEST}" $'xserver-xorg-core\t2:1\\.20\\.13-fake1'
    expect "rootfs: the L4T packages are installed" "${MANIFEST}" $'nvidia-l4t-core\t1\\.0~noble'
    expect "rootfs: the installation flags are gone" \
        "$(printf '%s\n' "${LISTING}" | grep -c 'nv-l4t-disable-boot-fw\|switchroot/image_prep' || true)" '^0$'
    expect "rootfs: the compat package is installed" "${MANIFEST}" $'libicu70:amd64\t'
    expect "rootfs: the compat source is kept" "${LISTING}" 'etc/apt/sources\.list\.d/nxd-compat\.sources'
    expect "rootfs: the Debian side is installed" "${MANIFEST}" $'ca-certificates\t'
    expect "rootfs: dpkg knows the packages (manifest from dpkg-query)" "${MANIFEST}" $'switch-bsp\t'
    expect "rootfs: the user has uid 1000" "$(tar -xOf "${TAR}" ./etc/passwd)" '^manu:x:1000:1000:'
    expect "rootfs: the user has a home" "${LISTING}" 'home/manu/\.bashrc'
    # shellcheck disable=SC2016
    expect "rootfs: the password is hashed" "$(tar -xOf "${TAR}" ./etc/shadow)" '^manu:\$6\$'
    expect "rootfs: the plain password is nowhere" \
        "$(tar -xOf "${TAR}" ./etc/shadow | grep -c 's3cret' || true)" '^0$'
    expect "rootfs: no nxd-user file left" \
        "$(printf '%s\n' "${LISTING}" | grep -c 'tmp/nxd-user' || true)" '^0$'
    expect "rootfs: the dpkg excludes are in the image" "${LISTING}" 'etc/dpkg/dpkg\.cfg\.d/nxd-excludes'
    expect "rootfs: package docs are not shipped" \
        "$(printf '%s\n' "${LISTING}" | grep -E '^-.* \./usr/share/doc/[^/]+/.+' | grep -vc '/copyright' || true)" '^0$'
    expect "rootfs: masked units point at /dev/null" "${LISTING}" 'etc/systemd/system/apt-daily\.timer -> /dev/null'
    expect "rootfs: the mask list is consumed" \
        "$(printf '%s\n' "${LISTING}" | grep -c 'tmp/nxd-mask' || true)" '^0$'
    expect "rootfs: the hostname survives the build" "$(tar -xOf "${TAR}" ./etc/hostname)" '^nintendo-switch$'
    expect "rootfs: the release package is installed" "${MANIFEST}" $'fake-release\t'
    expect "rootfs: nx-debian's own nxd-common is installed" "${MANIFEST}" $'nxd-common\t'
    expect "rootfs: the release package files are there" "${LISTING}" 'opt/fake/hello'
    expect "rootfs: no release debs left behind" \
        "$(printf '%s\n' "${LISTING}" | grep -c 'tmp/nxd-debs' || true)" '^0$'
    expect "rootfs: the hook of the variant ran" "${LISTING}" ' \./nxd-variant-hook$'
    expect "rootfs: the hook of another variant did not" \
        "$(printf '%s\n' "${LISTING}" | grep -c 'nxd-other-hook' || true)" '^0$'
    expect "rootfs: lightdm is told not to wait for logind" \
        "$(tar -xOf "${TAR}" ./etc/lightdm/lightdm.conf.d/10-nxd-seat.conf)" '^logind-check-graphical=false$'
    expect "rootfs: fstab mounts root by label" "$(tar -xOf "${TAR}" ./etc/fstab)" '^LABEL=NXDEB +/ +ext4'
    expect "rootfs: lightdm logs the user in" \
        "$(tar -xOf "${TAR}" ./etc/lightdm/lightdm.conf.d/50-nxd-autologin.conf)" '^autologin-user=manu$'
    expect "rootfs: the user is in adm" "$(tar -xOf "${TAR}" ./etc/group)" '^adm:.*manu'
    expect "rootfs: the copyright files are kept" "${LISTING}" 'usr/share/doc/[^/]+/copyright'
    expect "rootfs: the output is not left to root only" \
        "$(stat -c '%u' "${TAR}")" "^$(stat -c '%u' "${WORK}")\$"
else
    bad "rootfs: the tarball exists"
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
