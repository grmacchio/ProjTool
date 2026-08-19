#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: rem SCOPE -f TARGET

Examples:
  rem build -f dissertation_template
  rem media -f dissertation_template
  rem output -f dissertation_template
a
Scopes:
  build               Remove TARGET/build
  media               Remove TARGET/media
  output              Remove both TARGET/build and TARGET/media
EOF
}

die() {
    printf 'rem: %s\n' "$*" >&2
    exit 1
}

remove_directory() {
    local directory="$1"

    if [[ -d "$directory" || -L "$directory" ]]; then
        rm -rf -- "$directory"
        printf '→ removing %s\n' "$directory"
    fi
}

[[ $# -eq 0 ]] && { usage; exit 2; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
[[ $# -eq 3 ]] || { usage >&2; exit 2; }

SCOPE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
[[ "$2" == "-f" ]] || die "expected -f TARGET"
TARGET="$3"

case "$SCOPE" in
    build|media|output) ;;
    *) die "unsupported scope: $SCOPE" ;;
esac

if [[ -d "$TARGET" ]]; then
    TARGET_DIR="$(cd -- "$TARGET" && pwd)"
elif [[ -d "$COLLECTION_DIR/$TARGET" ]]; then
    TARGET_DIR="$(cd -- "$COLLECTION_DIR/$TARGET" && pwd)"
else
    die "target not found: $TARGET"
fi

BUILD_DIR="$TARGET_DIR/build"
MEDIA_DIR="$TARGET_DIR/media"

case "$SCOPE" in
    build)
        remove_directory "$BUILD_DIR"
        ;;
    media)
        remove_directory "$MEDIA_DIR"
        ;;
    output)
        remove_directory "$BUILD_DIR"
        remove_directory "$MEDIA_DIR"
        ;;
esac

printf '✓ %s removed from %s\n' "$SCOPE" "$(basename -- "$TARGET_DIR")"
