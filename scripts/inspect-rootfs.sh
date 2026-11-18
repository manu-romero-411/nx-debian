#!/usr/bin/env bash
# Reports on the rootfs.tar of a variant (see inspect_rootfs.py): size, heaviest
# packages, who pulled in what, image hygiene, boot files, services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

VARIANT="xfce"
OUTPUT="${NXD_OUTPUT_DIR}"
EXTRA=()

usage() {
    cat << EOF
Usage: inspect-rootfs.sh [options]

  --variant NAME   variant to inspect (default: ${VARIANT})
  --output DIR     directory given to nxd rootfs (default: ${OUTPUT})
  --why PKG        also explain who pulls PKG in (repeatable)
  --top N          how many of the heaviest packages to list
  -h, --help       this text

The report is also written to <output>/<variant>/report.txt.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:?missing value}"; shift 2 ;;
        --output) OUTPUT="${2:?missing value}"; shift 2 ;;
        --why) EXTRA+=(--why "${2:?missing value}"); shift 2 ;;
        --top) EXTRA+=(--top "${2:?missing value}"); shift 2 ;;
        -h | --help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

TARBALL="${OUTPUT}/${VARIANT}/rootfs.tar"
[[ -f "${TARBALL}" ]] || die "no rootfs at ${TARBALL} (run: nxd rootfs --variant ${VARIANT})"
need_cmd python3 "install python3"

PACKAGES="$(mktemp)"
trap 'rm -f "${PACKAGES}"' EXIT
variant_packages "${VARIANT}" > "${PACKAGES}"

REPORT="${OUTPUT}/${VARIANT}/report.txt"
if ! : > "${REPORT}" 2> /dev/null; then
    warn "cannot write ${REPORT} (owned by root? try: sudo chown -R \"\$USER\" ${OUTPUT}); printing only"
    REPORT=/dev/null
fi
python3 -I "${SCRIPT_DIR}/inspect_rootfs.py" "${TARBALL}" --packages "${PACKAGES}" \
    "${EXTRA[@]}" | tee "${REPORT}"
