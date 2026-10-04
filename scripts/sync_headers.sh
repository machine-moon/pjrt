#!/usr/bin/env bash
#
# sync_headers.sh - vendor the public PJRT C ABI headers from openxla/xla.
#
# Usage:
#   scripts/sync_headers.sh          refresh xla/ and the README headers line
#   scripts/sync_headers.sh --check  report drift and exit 1 (changes nothing)
#
# Inputs:
#   XLA_REF   openxla/xla ref to export (branch, tag or commit). Default: main.
#
# Outputs (write mode):
#   xla/pjrt/c/**, xla/pjrt/extensions/**, xla/backends/profiler/plugin/**
#   README.md   the line between the "headers" markers
#   VERSION     machine-readable provenance (XLA commit + PJRT API version)
#
# Everything else under xla/ (e.g. xla/pjrt/pjrt_loader.h) is never touched.
#
# Requirements: git, diff, awk, find, sed.
set -euo pipefail

# --- configuration ---------------------------------------------------------
XLA_REF=${XLA_REF:-main}
README=README.md
MARK_BEGIN='<!-- headers:begin -->'
MARK_END='<!-- headers:end -->'

# The upstream subtrees we manage, relative to xla/.
MANAGED=(
    pjrt/c
    pjrt/extensions
    backends/profiler/plugin
)

# --- arguments -------------------------------------------------------------
mode=write
case ${1:-} in
    '')      mode=write ;;
    --check) mode=check ;;
    *)       echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

# --- work area -------------------------------------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
checkout=$work/checkout     # sparse git checkout of openxla/xla
export_dir=$work/export     # filtered copy of the headers we vendor

# --- 1. fetch only the managed subtrees ------------------------------------
echo "fetching openxla/xla@$XLA_REF"
git -c advice.detachedHead=false init -q "$checkout"
git -C "$checkout" remote add origin https://github.com/openxla/xla
git -C "$checkout" fetch -q --depth 1 --filter=blob:none origin "$XLA_REF"
git -C "$checkout" sparse-checkout init --cone

sparse_paths=()
for path in "${MANAGED[@]}"; do
    sparse_paths+=("xla/$path")
done
git -C "$checkout" sparse-checkout set "${sparse_paths[@]}"
git -C "$checkout" checkout -q FETCH_HEAD

src=$checkout/xla

# every managed subtree must exist upstream
for path in "${MANAGED[@]}"; do
    if [ ! -d "$src/$path" ]; then
        echo "sync_headers.sh: upstream is missing xla/$path" >&2
        exit 1
    fi
done

# --- 2. copy the public files ----------------------------------------------
mkdir -p "$export_dir/pjrt/c" "$export_dir/backends/profiler/plugin"

# xla/pjrt/c: public headers and markdown, no internals/tests/docs
find "$src/pjrt/c" -type f ! -path '*/docs/*' \
    \( -name '*.h' -o -name '*.md' \) \
    ! -name '*_internal.h' ! -name '*_external.h' \
    ! -name '*wrapper_impl.h' ! -name '*test*' \
    -exec cp {} "$export_dir/pjrt/c/" \;

# xla/pjrt/extensions: keep the subtree, no internals/tests/examples
find "$src/pjrt/extensions" -type f -name '*.h' ! -path '*/example/*' \
    ! -name '*_internal.h' ! -name '*interface_impl.h' ! -name '*test*' -print0 |
while IFS= read -r -d '' file; do
    relative=${file#"$src/"}                # e.g. pjrt/extensions/foo/bar.h
    mkdir -p "$export_dir/$(dirname "$relative")"
    cp "$file" "$export_dir/$relative"
done

# xla/backends/profiler/plugin: profiler_c_api.h
find "$src/backends/profiler/plugin" -type f -name '*.h' \
    ! -name '*tracer*' ! -name 'plugin_metadata.h' \
    ! -name 'profiler_error.h' ! -name '*test*' \
    -exec cp {} "$export_dir/backends/profiler/plugin/" \;

# --- 3. the README provenance line -----------------------------------------
minor=$(sed -n 's/^#define PJRT_API_MINOR //p' "$export_dir/pjrt/c/pjrt_c_api.h")
if [ -z "$minor" ]; then
    echo "sync_headers.sh: PJRT_API_MINOR not found in pjrt_c_api.h" >&2
    exit 1
fi
commit=$(git -C "$checkout" rev-parse HEAD)
short=${commit:0:8}
line_file=$work/headers-line
echo "PJRT C ABI headers from [OpenXLA](https://github.com/openxla/xla) at [\`$short\`](https://github.com/openxla/xla/commit/$commit) — API version \`0.$minor\`." > "$line_file"

version_file=$work/VERSION
printf 'openxla/xla %s\npjrt api 0.%s\n' "$commit" "$minor" > "$version_file"

# print the README lines between the markers
readme_block() {
    awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
        index($0, begin) { inside=1; next }
        index($0, end)   { inside=0 }
        inside           { print }
    ' "$README"
}

# put the contents of file $1 between the markers
readme_set() {
    awk -v begin="$MARK_BEGIN" -v end="$MARK_END" -v block="$1" '
        index($0, begin) { print; while ((getline l < block) > 0) print l; close(block); skip=1; next }
        index($0, end)   { skip=0 }
        !skip            { print }
    ' "$README" > "$README.new"
    mv "$README.new" "$README"
}

# --- 3b. sanity: never wipe xla/ with a broken export ----------------------
if [ ! -f "$export_dir/pjrt/c/pjrt_c_api.h" ]; then
    echo "sync_headers.sh: export is missing pjrt_c_api.h" >&2
    exit 1
fi
count=$(find "$export_dir" -type f | wc -l)
if [ "$count" -lt 30 ]; then
    echo "sync_headers.sh: export has only $count files; refusing to continue" >&2
    exit 1
fi
if ! grep -qF "$MARK_BEGIN" "$README" || ! grep -qF "$MARK_END" "$README"; then
    echo "sync_headers.sh: $README is missing the headers markers" >&2
    exit 1
fi

# --- 4. compare or install -------------------------------------------------
if [ "$mode" = check ]; then
    drift=0
    for path in "${MANAGED[@]}"; do
        if ! diff -rq "$export_dir/$path" "xla/$path" >/dev/null 2>&1; then
            echo "drift: xla/$path"
            diff -rq "$export_dir/$path" "xla/$path" | sed 's/^/    /'
            drift=1
        fi
    done
    if ! diff <(readme_block) "$line_file" >/dev/null 2>&1; then
        echo "drift: $README"
        diff <(readme_block) "$line_file" | sed 's/^/    /'
        drift=1
    fi
    if ! diff VERSION "$version_file" >/dev/null 2>&1; then
        echo "drift: VERSION"
        diff VERSION "$version_file" | sed 's/^/    /'
        drift=1
    fi
    [ "$drift" = 0 ] || exit 1
    echo "up to date: pjrt 0.$minor (openxla/xla@$short)"
    exit 0
fi

for path in "${MANAGED[@]}"; do
    rm -rf "xla/$path"
done
mkdir -p xla
cp -r "$export_dir/." xla/
readme_set "$line_file"
cp "$version_file" VERSION
echo "wrote xla/, $README and VERSION: pjrt 0.$minor (openxla/xla@$short)"
