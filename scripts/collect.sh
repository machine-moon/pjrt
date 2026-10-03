#!/usr/bin/env bash
#
# collect.sh - extract the newest PJRT runtimes from public PyPI wheels.
#
# Usage:
#   scripts/collect.sh [OUT]     OUT defaults to build/
#
# For each package in SPEC it downloads the newest release wheel and extracts
# its shared library into OUT/{family}/{variant}/{arch}/. Files already present
# are skipped, so re-running is cheap and idempotent.
#
# Requirements: curl, unzip.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

out=${1:-build}
wheel_file=$(mktemp)
trap 'rm -f "$wheel_file"' EXIT

# Print the newest release's wheel URLs for a PyPI package.
# The PyPI JSON is a single line; its top-level "urls" array holds the latest
# release's files, so keep the text between '"urls":[' and the next ']'.
latest_wheels() {
    local package=$1
    local json urls
    json=$(curl -fsSL "https://pypi.org/pypi/$package/json")
    urls=${json#*'"urls":['}
    if [ "$urls" = "$json" ]; then
        echo "collect.sh: no 'urls' array in PyPI JSON for $package" >&2
        return 1
    fi
    urls=${urls%%]*}
    echo "$urls" | grep -oE 'https://files\.pythonhosted\.org/[^"]+\.whl' || {
        echo "collect.sh: no wheels listed for $package" >&2
        return 1
    }
}

# Map a wheel filename to an architecture directory name.
arch_of() {
    case $1 in
        *aarch64*)        echo aarch64 ;;
        *arm64*)          echo arm64 ;;
        *x86_64*|*amd64*) echo x86_64 ;;
        *)                return 1 ;;
    esac
}

# Verify a shared library matches its arch directory. Data files are skipped.
check_arch() {
    local file=$1 arch=$2 token desc
    case $file in *.so|*.dylib) ;; *) return 0 ;; esac
    command -v file >/dev/null || return 0
    case $arch in
        x86_64)  token=x86-64 ;;
        aarch64) token=aarch64 ;;
        arm64)   token=arm64 ;;
        *)       return 0 ;;
    esac
    desc=$(file -b "$file")
    case $desc in
        *"$token"*) return 0 ;;
    esac
    echo "collect.sh: $file does not look like $arch: $desc" >&2
    return 1
}

# The packages we collect: family|variant|package|library(ies).
# variant is empty for families without a version (cpu, xpu, tpu, mps).
spec() {
    echo 'cpu||xla-cpu-pjrt|xla_cpu_pjrt.so'
    echo 'cuda|11|jax-cuda11-pjrt|xla_cuda_plugin.so'
    echo 'cuda|12|jax-cuda12-pjrt|xla_cuda_plugin.so'
    echo 'cuda|13|jax-cuda13-pjrt|xla_cuda_plugin.so'
    echo 'rocm|6|jax-rocm60-pjrt|xla_rocm_plugin.so'
    echo 'rocm|7|jax-rocm7-pjrt|xla_rocm_plugin.so'
    echo 'rocm|10|jax-rocm10-pjrt|xla_rocm_plugin.so'
    echo 'xpu||jax-oneapi-pjrt|xla_oneapi_plugin.so'
    echo 'tpu||libtpu|libtpu.so'
    echo 'mps||jax-mps|libpjrt_plugin_mps.dylib mlx.metallib'
    # shelved: OpenXLA CUDA flavor (xla-cuda12/13-pjrt 0.0.1), not shipped
    #echo 'generic/cuda12|xla-cuda12-pjrt|xla_gpu_pjrt.so'
    #echo 'generic/cuda13|xla-cuda13-pjrt|xla_gpu_pjrt.so'
}

main() {
    local family variant package files url arch dir missing lib wheels
    while IFS='|' read -r family variant package files; do
        wheels=$(latest_wheels "$package") || exit 1
        while read -r url; do
            arch=$(arch_of "${url##*/}") || continue
            dir=$out/$family${variant:+/$variant}/$arch

            # skip when every library is already present
            missing=0
            for lib in $files; do [ -e "$dir/$lib" ] || missing=1; done
            [ "$missing" = 0 ] && continue

            mkdir -p "$dir"
            curl -fsSL --retry 3 "$url" -o "$wheel_file"
            for lib in $files; do
                unzip -p "$wheel_file" "*/$lib" > "$dir/$lib.new"
                mv "$dir/$lib.new" "$dir/$lib"
                check_arch "$dir/$lib" "$arch" || exit 1
                echo "[ok] $dir/$lib"
            done
        done <<<"$wheels"
    done < <(spec)
}

main
