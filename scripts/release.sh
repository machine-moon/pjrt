#!/usr/bin/env bash
#
# release.sh - publish the collected runtimes as one daily GitHub release.
#
# Usage:
#   GH_TOKEN=... scripts/release.sh     publish tag pjrt-YYYY-MM-DD
#   scripts/release.sh --dry-run        print tag/notes/assets, change nothing
#
# Steps:
#   1. collect runtimes (idempotent)
#   2. build the release notes (README headers line + a runtimes tree)
#   3. skip if today's tag already exists
#   4. stage flat, path-encoded assets
#   5. gh release create
#
# Requirements: gh (unless --dry-run); curl and unzip via collect.sh.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

dry_run=0
if [ "${1:-}" = --dry-run ]; then
    dry_run=1
fi

if [ "$dry_run" = 0 ]; then
    command -v gh >/dev/null || { echo "release.sh: gh not found (or use --dry-run)" >&2; exit 1; }
    : "${GH_TOKEN:?release.sh: export GH_TOKEN}"
fi

# --- 1. collect runtimes ---------------------------------------------------
bash scripts/collect.sh

# --- 2. release notes ------------------------------------------------------
# The README headers line is already a link to the exact OpenXLA commit.
date=$(date -u +%F)
tag="pjrt-$date"
line=$(awk '/<!-- headers:begin -->/{inside=1;next} /<!-- headers:end -->/{inside=0} inside' README.md)

# a tree view of build/ (falls back to a flat list if `tree` is missing)
tree_of_build() {
    if command -v tree >/dev/null; then
        (cd build && tree --noreport . | tail -n +2)
    else
        (cd build && find . -type f | sort | sed 's|^\./|  |')
    fi
}

fence='```'
notes="$line

### Runtimes
${fence}
$(tree_of_build)
${fence}"

if [ "$dry_run" = 1 ]; then
    echo "tag: $tag"
    echo "$notes"
    exit 0
fi

# refuse to publish an empty set (an unmatched "$stage"/* glob would error)
if [ -z "$(find build -type f -print -quit)" ]; then
    echo "release.sh: build/ is empty; nothing to release" >&2
    exit 1
fi

# --- 3. one release per day ------------------------------------------------
if gh release view "$tag" >/dev/null 2>&1; then
    echo "skip $tag (already exists)"
    exit 0
fi

# --- 4. stage assets -------------------------------------------------------
# Asset names are flat: cuda/12/x86_64/x.so -> cuda__12__x86_64__x.so
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
while IFS= read -r -d '' file; do
    relative=${file#build/}
    encoded=${relative//\//__}
    cp "$file" "$stage/$encoded"
done < <(find build -type f -print0)

# --- 5. publish ------------------------------------------------------------
gh release create "$tag" --title "PJRT $date" --notes "$notes" "$stage"/*
echo "released $tag"
