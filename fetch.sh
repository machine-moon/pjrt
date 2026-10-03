#!/usr/bin/env bash
#
# fetch.sh - download PJRT runtimes from the latest release into this tree.
#
# Usage: fetch.sh [-b] [-f] <command>
#   all      everything in the release
#   cpu      CPU plugin for this arch            (*)
#   cuda11   cuda 11 (x86_64)
#   cuda12   cuda 12 for this arch               (*)
#   cuda13   cuda 13 for this arch               (*)
#   rocm6    rocm 6 (x86_64)
#   rocm7    rocm 7 (x86_64)
#   rocm10   rocm 10 (x86_64)
#   xpu      xpu (x86_64)
#   tpu      tpu (x86_64)
#   mps      apple mps (arm64)
#
#   (*) has multiple architectures; -b fetches all of them, otherwise the arch
#       is taken from uname -m. A device command also fetches the CPU plugin
#       for the same arch. -f / --force re-downloads existing files.
set -euo pipefail

base=${PJRT_BASE:-https://github.com/machine-moon/pjrt/releases/latest/download}

# command|family|variant|arch|library
tree() {
    echo 'cpu|cpu||x86_64|xla_cpu_pjrt.so'
    echo 'cpu|cpu||aarch64|xla_cpu_pjrt.so'
    echo 'cuda11|cuda|11|x86_64|xla_cuda_plugin.so'
    echo 'cuda12|cuda|12|x86_64|xla_cuda_plugin.so'
    echo 'cuda12|cuda|12|aarch64|xla_cuda_plugin.so'
    echo 'cuda13|cuda|13|x86_64|xla_cuda_plugin.so'
    echo 'cuda13|cuda|13|aarch64|xla_cuda_plugin.so'
    echo 'rocm6|rocm|6|x86_64|xla_rocm_plugin.so'
    echo 'rocm7|rocm|7|x86_64|xla_rocm_plugin.so'
    echo 'rocm10|rocm|10|x86_64|xla_rocm_plugin.so'
    echo 'xpu|xpu||x86_64|xla_oneapi_plugin.so'
    echo 'tpu|tpu||x86_64|libtpu.so'
    echo 'mps|mps||arm64|libpjrt_plugin_mps.dylib'
    echo 'mps|mps||arm64|mlx.metallib'
}

usage() {
    echo 'usage: fetch.sh [-b] [-f] <command>'
    echo
    echo '  all      everything in the release'
    echo '  cpu      CPU plugin for this arch            (*)'
    echo '  cuda11   cuda 11 (x86_64)'
    echo '  cuda12   cuda 12 for this arch               (*)'
    echo '  cuda13   cuda 13 for this arch               (*)'
    echo '  rocm6    rocm 6 (x86_64)'
    echo '  rocm7    rocm 7 (x86_64)'
    echo '  rocm10   rocm 10 (x86_64)'
    echo '  xpu      xpu (x86_64)'
    echo '  tpu      tpu (x86_64)'
    echo '  mps      apple mps (arm64)'
    echo
    echo '  (*) has multiple architectures; -b fetches all of them, otherwise the'
    echo '      arch comes from uname -m (or you are told to be explicit).'
    echo '      a device command also fetches the CPU plugin for the same arch.'
    echo '  -f / --force  re-download files that already exist.'
}

# download <family> <variant> <arch> <library> into <family>[/<variant>]/<arch>/
get() {
    local family=$1 variant=$2 arch=$3 library=$4 path
    path=$family/$arch/$library
    if [ -n "$variant" ]; then
        path=$family/$variant/$arch/$library
    fi
    if [ -e "$path" ] && [ -z "$force" ]; then
        echo "have  $path"
    else
        echo "get   $path"
        # download to .part, then move: a failed/partial download never becomes
        # a file that later runs treat as present.
        curl -fL --retry 3 --create-dirs -o "$path.part" "$base/${path//\//__}"
        mv "$path.part" "$path"
    fi
}

# print the tree lines for a command + arch as family|variant|arch|library
lines_for() {
    local command=$1 arch=$2 c family variant a library
    while IFS='|' read -r c family variant a library; do
        if [ "$c" = "$command" ] && [ "$a" = "$arch" ]; then
            echo "$family|$variant|$a|$library"
        fi
    done < <(tree)
}

# the architectures available for a command
arches_of() {
    local command=$1 c family variant arch library
    while IFS='|' read -r c family variant arch library; do
        if [ "$c" = "$command" ]; then
            echo "$arch"
        fi
    done < <(tree) | sort -u
}

# fetch <command> <arch>, plus the CPU plugin for that arch
fetch_one() {
    local command=$1 arch=$2 family variant a library
    while IFS='|' read -r family variant a library; do
        get "$family" "$variant" "$a" "$library"
    done < <(lines_for "$command" "$arch")
    if [ "$command" != cpu ]; then
        while IFS='|' read -r family variant a library; do
            get "$family" "$variant" "$a" "$library"
        done < <(lines_for cpu "$arch")
    fi
}

# --- command line ----------------------------------------------------------
command=; both=0; force=
for arg in "$@"; do
    case $arg in
        -b|--both)  both=1 ;;
        -f|--force) force=1 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "fetch.sh: unknown option: $arg" >&2; usage; exit 2 ;;
        *)          command=$arg ;;
    esac
done
[ -n "$command" ] || { usage; exit 1; }

if [ "$command" = all ]; then
    while IFS='|' read -r c family variant arch library; do
        get "$family" "$variant" "$arch" "$library"
    done < <(tree)
    exit 0
fi

# split an explicit <command>-<arch>
device=$command; arch=
case $command in
    *-x86_64)  device=${command%-x86_64};  arch=x86_64 ;;
    *-aarch64) device=${command%-aarch64}; arch=aarch64 ;;
    *-arm64)   device=${command%-arm64};   arch=arm64 ;;
esac

arches=$(arches_of "$device")
if [ -z "$arches" ]; then
    echo "fetch.sh: unknown command: $device" >&2
    usage
    exit 2
fi

if [ -n "$arch" ]; then
    if ! echo "$arches" | grep -qx "$arch"; then
        echo "fetch.sh: '$device' has no '$arch' build" >&2
        exit 2
    fi
    targets=$arch
elif [ "$both" = 1 ]; then
    targets=$arches
elif [ "$(echo "$arches" | wc -l)" = 1 ]; then
    # single-arch command: just get it, no uname needed
    targets=$arches
else
    host=$(uname -m)
    if [ "$host" = amd64 ]; then host=x86_64; fi
    if echo "$arches" | grep -qx "$host"; then
        targets=$host
    elif [ "$host" = arm64 ] && [ "$device" = cpu ]; then
        echo "fetch.sh: macOS has no standalone CPU plugin (CPU is built into jaxlib)." >&2
        echo "          use './fetch.sh mps' for the Apple GPU." >&2
        exit 1
    else
        echo "fetch.sh: sorry, couldn't auto-detect the architecture for '$device'" >&2
        echo "          (uname -m = $(uname -m)). please be explicit:" >&2
        for a in $arches; do
            echo "              ./fetch.sh $device-$a" >&2
        done
        exit 1
    fi
fi

for a in $targets; do
    fetch_one "$device" "$a"
done
