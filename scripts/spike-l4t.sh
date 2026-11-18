#!/usr/bin/env bash
# Can Debian and the L4T repository share one apt setup?
#
# Simulates (apt-get -s, nothing is installed) the installation of a
# variant's package set on a fresh Debian, with each L4T component and with
# and without the pins of config/apt/l4t.pref, and writes a report: names
# Debian does not have, unmet dependencies, which source every L4T package
# comes from, and (with --contents) which L4T package ships what.
#
# Needs apt only: no root, no chroot, no emulation, so it also runs natively
# in an arm64 container on an arm64 machine. See docs/rootfs.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"
load_config

VARIANT="xfce"
COMPONENTS="${NXD_SPIKE_COMPONENTS:-jammy noble}"
KEYRING="${NXD_SPIKE_KEYRING:-/usr/share/keyrings/debian-archive-keyring.gpg}"
REPORT="${PWD}/spike-report.md"
WORKDIR=""
KEEP=0
CONTENTS=0

# Packages whose availability in the Debian suite changes the plan.
EXTRAS=(
    xfce4-volumed-pulse
    xubuntu-default-settings
    onboard
    openbox
    xfce4-genmon-plugin
    systemd-zram-generator
    joycond
    nvpmodel
)

usage() {
    cat << EOF
Usage: spike-l4t.sh [options]

  --variant NAME         variant whose package set is simulated (default: ${VARIANT})
  --components "A B"     L4T components to try (default: "${COMPONENTS}")
  --suite SUITE          Debian suite (default: ${NXD_SUITE})
  --arch ARCH            architecture (default: ${NXD_ARCH})
  --mirror URL           Debian mirror (default: ${NXD_MIRROR})
  --keyring FILE         archive keyring of that suite (default: ${KEYRING})
  --contents             also download the L4T packages and list what they ship
  --report FILE          where to write the report (default: ${REPORT})
  --workdir DIR          keep apt state and downloads here (default: temporary)
  --keep                 do not delete the temporary work directory
  -h, --help             this text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:?--variant needs a value}"; shift 2 ;;
        --components) COMPONENTS="${2:?--components needs a value}"; shift 2 ;;
        --suite) NXD_SUITE="${2:?--suite needs a value}"; shift 2 ;;
        --arch) NXD_ARCH="${2:?--arch needs a value}"; shift 2 ;;
        --mirror) NXD_MIRROR="${2:?--mirror needs a value}"; shift 2 ;;
        --keyring) KEYRING="${2:?--keyring needs a value}"; shift 2 ;;
        --contents) CONTENTS=1; shift ;;
        --report) REPORT="${2:?--report needs a value}"; shift 2 ;;
        --workdir) WORKDIR="${2:?--workdir needs a value}"; KEEP=1; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

need_cmd apt-get "run this on a Debian or Ubuntu host, or in a container (nxd container spike)"
need_cmd apt-cache "run this on a Debian or Ubuntu host, or in a container (nxd container spike)"
need_cmd dpkg-deb "install dpkg"
[[ -f "${KEYRING}" ]] || die "archive keyring not found: ${KEYRING} (apt install debian-archive-keyring, or pass --keyring)"
verify_key "${NXD_L4T_KEY}" "${NXD_L4T_KEY_FPR}"

if [[ -z "${WORKDIR}" ]]; then
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/nxd-spike.XXXXXX")"
fi
mkdir -p "${WORKDIR}"
if [[ "${KEEP}" -eq 0 ]]; then
    trap 'rm -rf "${WORKDIR}"' EXIT
fi

mapfile -t ALL_PKGS < <(variant_packages "${VARIANT}")
mapfile -t L4T_PKGS < <(read_list "${NXD_CONFIG_DIR}/packages/l4t.list")
DEBIAN_PKGS=()
for pkg in "${ALL_PKGS[@]}"; do
    keep=1
    for l4t in "${L4T_PKGS[@]}"; do
        if [[ "${pkg}" == "${l4t}" ]]; then
            keep=0
            break
        fi
    done
    if [[ "${keep}" -eq 1 ]]; then
        DEBIAN_PKGS+=("${pkg}")
    fi
done

L4T_HOST="$(url_host "${NXD_L4T_URL}")"
APT_OPTS=()

# make_env NAME COMPONENT PINS: a private apt root for one scenario. COMPONENT
# empty means no L4T repository. PINS is "pin" or "nopin".
make_env() {
    local name="$1" component="$2" pins="$3" dir="${WORKDIR}/$1"
    mkdir -p "${dir}/lists/partial" "${dir}/archives/partial"
    : > "${dir}/status"
    {
        printf 'deb [arch=%s signed-by=%s] %s %s %s\n' \
            "${NXD_ARCH}" "${KEYRING}" "${NXD_MIRROR}" "${NXD_SUITE}" "${NXD_COMPONENTS}"
        if [[ -n "${component}" ]]; then
            l4t_source_line "${NXD_ARCH}" "${NXD_L4T_KEY}" "${component}"
            if [[ -n "${NXD_COMPAT_SUITE}" ]]; then
                printf 'deb [arch=%s signed-by=%s] %s %s %s\n' \
                    "${NXD_ARCH}" "${KEYRING}" "${NXD_MIRROR}" "${NXD_COMPAT_SUITE}" "${NXD_COMPONENTS}"
            fi
        fi
    } > "${dir}/sources.list"
    mkdir -p "${dir}/empty"
    : > "${dir}/preferences"
    if [[ -n "${component}" ]]; then
        render_compat_pins >> "${dir}/preferences"
        printf '\n' >> "${dir}/preferences"
    fi
    if [[ "${pins}" == "pin" ]]; then
        render_pins "${L4T_HOST}" >> "${dir}/preferences"
    fi
    APT_OPTS=(
        -o "Dir::Etc::sourcelist=${dir}/sources.list"
        -o "Dir::Etc::sourceparts=${dir}/empty"
        -o "Dir::Etc::preferences=${dir}/preferences"
        -o "Dir::Etc::preferencesparts=${dir}/empty"
        -o "Dir::State=${dir}"
        -o "Dir::State::lists=${dir}/lists"
        -o "Dir::State::status=${dir}/status"
        -o "Dir::Cache=${dir}"
        -o "Dir::Cache::archives=${dir}/archives"
        -o "APT::Architecture=${NXD_ARCH}"
        -o "APT::Architectures::=${NXD_ARCH}"
        -o "APT::Install-Recommends=false"
        -o "APT::Get::Assume-Yes=true"
        -o "Debug::NoLocking=true"
    )
}

# missing_names PKG...: the names no source of the current environment has.
missing_names() {
    local pkg
    for pkg in "$@"; do
        if ! apt-cache "${APT_OPTS[@]}" show --no-all-versions "${pkg}" > /dev/null 2>&1; then
            printf '%s\n' "${pkg}"
        fi
    done
}

# candidate_source PKG: "version  priority  source" of the version apt would pick.
candidate_source() {
    apt-cache "${APT_OPTS[@]}" policy "$1" 2> /dev/null | awk '
        /^  Candidate:/ { cand = $2; next }
        /^     [^ ]/ { v = $1; prio = $2; next }
        /^ \*\*\* / { v = $2; prio = $3; next }
        /^        [ ]?[-0-9]/ && v == cand && !done { printf "%s  %s  %s %s\n", cand, prio, $2, $3; done = 1 }
        END { if (cand == "" || cand == "(none)") print "(none)" }
    '
}

emit() { printf '%s\n' "$*" >> "${REPORT}"; }
fence() { emit '```'; }

: > "${REPORT}"
emit "# nxd spike report"
emit ""
emit "- date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
emit "- Debian: ${NXD_SUITE} (${NXD_ARCH}) from ${NXD_MIRROR}"
emit "- L4T: ${NXD_L4T_URL} ${NXD_L4T_SUITE}, components tried: ${COMPONENTS}"
emit "- variant: ${VARIANT} (${#ALL_PKGS[@]} packages, ${#L4T_PKGS[@]} from L4T)"
emit ""

SUMMARY=()

# prepare_scenario NAME COMPONENT PINS: private apt root plus apt-get update.
# Returns 1 (after writing it to the report) when the update fails.
prepare_scenario() {
    local name="$1" dir="${WORKDIR}/$1"
    log "scenario ${name}: updating package lists..."
    make_env "$@"
    if apt-get "${APT_OPTS[@]}" -q update > "${dir}/update.txt" 2>&1; then
        return 0
    fi
    emit "## ${name}: UPDATE FAILED"
    emit ""
    fence
    emit "$(tail -n 15 "${dir}/update.txt")"
    fence
    emit ""
    SUMMARY+=("$(printf '%-28s %s' "${name}" "UPDATE FAILED")")
    return 1
}

# simulate_scenario NAME PKG...: apt-get -s install in the prepared scenario.
simulate_scenario() {
    local name="$1" dir="${WORKDIR}/$1" status=0 verdict unmet errors count
    shift
    log "scenario ${name}: simulating the installation..."
    apt-get "${APT_OPTS[@]}" -s install "$@" > "${dir}/sim.txt" 2>&1 || status=$?
    unmet="$(awk '/^The following packages have unmet dependencies:/ { f = 1; next } f && /^E:/ { f = 0 } f' "${dir}/sim.txt")"
    errors="$(grep '^E:' "${dir}/sim.txt" || true)"
    count="$(grep -c '^Inst ' "${dir}/sim.txt" || true)"
    if [[ "${status}" -eq 0 ]]; then
        verdict="OK (${count} packages)"
    elif [[ -n "${unmet}" ]]; then
        verdict="UNMET DEPENDENCIES"
    else
        verdict="FAILED"
    fi
    emit "## ${name}: ${verdict}"
    emit ""
    if [[ -n "${errors}" ]]; then
        fence
        emit "${errors}"
        fence
        emit ""
    fi
    if [[ -n "${unmet}" ]]; then
        emit "Unmet dependencies:"
        emit ""
        fence
        emit "${unmet}"
        fence
        emit ""
    fi
    SUMMARY+=("$(printf '%-28s %s' "${name}" "${verdict}")")
}

# 1. Debian alone: do the names exist, and does the Debian part resolve?
if prepare_scenario debian "" nopin; then
    mapfile -t MISSING < <(missing_names "${DEBIAN_PKGS[@]}")
    emit "## Names ${NXD_SUITE} does not have"
    emit ""
    if [[ ${#MISSING[@]} -eq 0 ]]; then
        emit "None: all ${#DEBIAN_PKGS[@]} Debian-side names exist."
    else
        fence
        printf '%s\n' "${MISSING[@]}" >> "${REPORT}"
        fence
    fi
    emit ""
    emit "## Packages that change the plan (Debian ${NXD_SUITE})"
    emit ""
    fence
    for pkg in "${EXTRAS[@]}"; do
        printf '%-28s %s\n' "${pkg}" "$(candidate_source "${pkg}")" >> "${REPORT}"
    done
    fence
    emit ""
    simulate_scenario debian "${DEBIAN_PKGS[@]}"
fi

# 2. Debian plus each L4T component, without and with the pins.
for component in ${COMPONENTS}; do
    for pins in nopin pin; do
        scenario="l4t-${component}-${pins}"
        if prepare_scenario "${scenario}" "${component}" "${pins}"; then
            simulate_scenario "${scenario}" "${ALL_PKGS[@]}"
            emit "Where the L4T packages come from (version, priority, source):"
            emit ""
            fence
            for pkg in "${L4T_PKGS[@]}" ${NXD_COMPAT_PACKAGES}; do
                printf '%-30s %s\n' "${pkg}" "$(candidate_source "${pkg}")" >> "${REPORT}"
            done
            fence
            emit ""
            emit "The packages that change the plan, with this repository:"
            emit ""
            fence
            for pkg in "${EXTRAS[@]}"; do
                printf '%-30s %s\n' "${pkg}" "$(candidate_source "${pkg}")" >> "${REPORT}"
            done
            fence
            emit ""
        fi
    done
done

# 3. What the L4T packages ship.
if [[ "${CONTENTS}" -eq 1 ]]; then
    last_component=""
    for component in ${COMPONENTS}; do
        last_component="${component}"
    done
    if [[ -n "${last_component}" ]]; then
        log "downloading the L4T packages of ${last_component}..."
        make_env "l4t-${last_component}-nopin" "${last_component}" nopin
        mkdir -p "${WORKDIR}/debs"
        for pkg in "${L4T_PKGS[@]}"; do
            (cd "${WORKDIR}/debs" && apt-get "${APT_OPTS[@]}" -q download "${pkg}" > /dev/null 2>&1) ||
                warn "could not download ${pkg}"
        done
        emit "## What the L4T packages (${last_component}) ship"
        emit ""
        fence
        for pattern in 'usr/sbin/nvpmodel$' 'nvpmodel.*\.conf$' 'polkit-1/actions/' \
            'usr/lib/xorg/Xorg$' 'nvidia_drv\.so$' 'bootstack/' 'modules\.tar' \
            'ucm2/' 'udev/rules\.d/' 'xorg\.conf\.d/' 'systemd/system/.*\.service$' 'opt/switchroot/'; do
            printf '%s\n' "--- ${pattern}" >> "${REPORT}"
            for deb in "${WORKDIR}"/debs/*.deb; do
                [[ -f "${deb}" ]] || continue
                dpkg-deb -c "${deb}" 2> /dev/null | awk '{ print $6 }' |
                    grep -E "${pattern}" | head -n 6 |
                    sed "s|^|$(dpkg-deb -f "${deb}" Package): |" >> "${REPORT}" || true
            done
        done
        fence
        emit ""
    fi
fi

printf '\n'
printf '%s\n' "${SUMMARY[@]}"
printf '\nReport: %s\n' "${REPORT}"
