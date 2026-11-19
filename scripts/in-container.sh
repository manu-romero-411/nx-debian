#!/usr/bin/env bash
# Runs `nxd` inside a Debian trixie container: the same apt and mmdebstrap as
# the CI, whatever the host distribution is (Fedora Asahi, for one).
#
#   scripts/in-container.sh spike --contents
#   sudo scripts/in-container.sh rootfs --variant xfce
#
# The container is privileged because mmdebstrap needs mount and chroot. Use a
# rootful engine (sudo) for `rootfs`; `spike` does not need it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

# The tag follows the Containerfile, so a changed one is rebuilt by itself.
IMAGE="${NXD_CONTAINER_IMAGE:-nxd-builder:$(sha256sum "${NXD_ROOT}/docker/Containerfile" | cut -c1-8)}"
ENGINE="${NXD_CONTAINER_ENGINE:-}"
if [[ -z "${ENGINE}" ]]; then
    for candidate in podman docker; do
        if command -v "${candidate}" > /dev/null 2>&1; then
            ENGINE="${candidate}"
            break
        fi
    done
fi
[[ -n "${ENGINE}" ]] || die "neither podman nor docker found (set NXD_CONTAINER_ENGINE)"

if ! "${ENGINE}" image inspect "${IMAGE}" > /dev/null 2>&1; then
    log "building the ${IMAGE} image..."
    "${ENGINE}" build -t "${IMAGE}" -f "${NXD_ROOT}/docker/Containerfile" "${NXD_ROOT}/docker"
fi

# A terminal (for the password prompt of --user) only when there is one.
TTY=()
if [[ -t 0 && -t 1 ]]; then
    TTY=(-it)
fi

exec "${ENGINE}" run --rm --privileged --security-opt label=disable "${TTY[@]}" \
    -v "${NXD_ROOT}:/nxd" -w /nxd \
    -e NXD_SUITE -e NXD_ARCH -e NXD_MIRROR -e NXD_L4T_COMPONENT -e NXD_OUTPUT_DIR \
    -e NXD_PASSWORD -e NXD_IMAGE_SIZE -e NXD_BOOT_NAME -e NXD_BOOT_ID -e GITHUB_TOKEN \
    "${IMAGE}" ./nxd "$@"
