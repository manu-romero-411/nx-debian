#!/bin/sh
# Runs inside the rootfs, for the retrobox variant only, after 10-retrobox-data.sh.
#
# Installs the emulators named in /tmp/nxd-emulators (NXD_EMULATORS) with their
# own installers, as the user of the image, into /retrobox/emulators: the
# installers are Retrobox's (/opt/retrobox/tools/emulators/NAME.sh -i). They
# use apt through sudo, which the image has no use for, so what they would
# install is installed here first: the libraries RetroArch needs are in
# config/packages/retrobox.list, the build tools (flycast is built from source
# on ARM) are installed now and purged, with what they brought, afterwards.
set -eu

list=/tmp/nxd-emulators
emulators=/opt/retrobox/tools/emulators
data=/retrobox
tools="build-essential git cmake unzip curl 7zip"

[ -s "${list}" ] || { rm -f "${list}"; exit 0; }
names="$(tr '\n' ' ' < "${list}")"

name="$(getent passwd 1000 | cut -d: -f1 || true)"
if [ -z "${name}" ]; then
    echo "20-retrobox-emulators: warning: no user with uid 1000 (--no-user?): no emulators installed" >&2
    rm -f "${list}"
    exit 0
fi
if [ ! -d "${emulators}" ]; then
    echo "20-retrobox-emulators: warning: ${emulators} is missing (--no-releases?): no emulators installed" >&2
    rm -f "${list}"
    exit 0
fi
group="$(id -gn "${name}")"
home="$(getent passwd "${name}" | cut -d: -f6)"

# RetroArch's installer has the buildbot's binary for aarch64 only in newer
# releases of retrobox-core: an older one would build it from source here, for
# the CPU that builds the image. It is left out then (Retrobox offers to
# install it at the first start), and the build says so.
arch="$(uname -m)"
todo=""
for emulator in ${names}; do
    script="${emulators}/${emulator}.sh"
    [ -x "${script}" ] || { echo "20-retrobox-emulators: no installer for ${emulator}" >&2; exit 1; }
    if [ "${emulator}" = retroarch ] && [ "${arch}" = aarch64 ] \
        && ! "${script}" -l | tr ' ' '\n' | grep -qx archive; then
        echo "20-retrobox-emulators: warning: this retrobox-core cannot install the RetroArch binary on aarch64: RetroArch is NOT in the image" >&2
        echo "20-retrobox-emulators: warning: build with --prereleases, or wait for a release newer than v0.7.1" >&2
        continue
    fi
    todo="${todo} ${emulator}"
done
names="${todo}"
[ -n "${names}" ] || { rm -f "${list}"; exit 0; }

# What the build tools bring is whatever dpkg lists after and not before.
packages_before="$(mktemp)"
packages_after="$(mktemp)"
dpkg-query -W -f '${Package}\n' | sort > "${packages_before}"
lists_before="$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' | wc -l)"
[ "${lists_before}" -gt 0 ] || apt-get update -qq
# shellcheck disable=SC2086 # the names are words
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${tools}
# the installer asks for `7z`; Debian's 7zip package may only have 7zz
created_link=""
if ! command -v 7z > /dev/null 2>&1; then
    for candidate in 7zz 7zr 7za; do
        if command -v "${candidate}" > /dev/null 2>&1; then
            ln -s "$(command -v "${candidate}")" /usr/local/bin/7z
            created_link=/usr/local/bin/7z
            break
        fi
    done
fi

# flycast's libretro build includes <GL/gl.h> (the installer of retrobox-core
# only asks for build-essential, git and cmake). libgl-dev is not installed:
# it depends on libx11-dev, which the L4T repository also has (as 2:1.8.7-1-l4t,
# tied to its own libx11-6), and apt cannot solve that next to Debian's libx11-6.
# The headers are all that is needed, and the build finds them by CPATH.
glinc=""
for emulator in ${names}; do
    [ "${emulator}" = retroarch ] || continue
    glinc="$(mktemp -d)"
    chmod 755 "${glinc}"
    (
        cd "${glinc}"
        # one by one: a package that is missing must not stop the others, the
        # check below says whether the three headers are there
        for package in libgl-dev libglx-dev libegl-dev libgles-dev libglvnd-core-dev; do
            apt-get download "${package}" || echo "20-retrobox-emulators: warning: cannot download ${package}" >&2
        done
        for deb in ./*.deb; do
            [ ! -f "${deb}" ] || dpkg-deb -x "${deb}" root
        done
    )
    for header in GL/gl.h GL/glext.h KHR/khrplatform.h; do
        [ -f "${glinc}/root/usr/include/${header}" ] \
            || { echo "20-retrobox-emulators: ${header} is not in the OpenGL development packages" >&2; exit 1; }
    done
    chmod -R a+rX "${glinc}"
done

mkdir -p "${data}"
chown "${name}:${group}" "${data}"
for emulator in ${names}; do
    echo "20-retrobox-emulators: installing ${emulator}"
    # RETROARCH_CFLAGS only matters if a source build is ever used: generic
    # ARMv8 tuned for the Switch's Cortex-A57, never -march=native, whose
    # result depends on the machine that builds the image
    runuser -u "${name}" -- env HOME="${home}" PYTHONPATH=/opt/retrobox/lib \
        RETROARCH_CFLAGS="-O3 -march=armv8-a -mtune=cortex-a57 -pipe" \
        CPATH="${glinc:+${glinc}/root/usr/include}" \
        "${emulators}/${emulator}.sh" -i
    [ -d "${data}/emulators/${emulator}/app" ] \
        || { echo "20-retrobox-emulators: ${emulator} is not in ${data}/emulators" >&2; exit 1; }
done

# purge the build tools and everything they brought
[ -z "${created_link}" ] || rm -f "${created_link}"
[ -z "${glinc}" ] || rm -rf "${glinc}"
dpkg-query -W -f '${Package}\n' | sort > "${packages_after}"
# shellcheck disable=SC2046 # the names are words
DEBIAN_FRONTEND=noninteractive apt-get purge -y $(comm -13 "${packages_before}" "${packages_after}")
apt-get clean
[ "${lists_before}" -gt 0 ] || rm -rf /var/lib/apt/lists/*
rm -f "${packages_before}" "${packages_after}" "${list}"
rm -rf "${data}/emulators/_src"
chown -R "${name}:${group}" "${data}" "${home}"
