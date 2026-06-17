#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CHANNEL="${CHANNEL:-stable}"
APP_NAME="${APP_NAME:-Android Dev Agent}"
SOURCE_PATH="${RELEASE_NOTES_SOURCE:-$ROOT/release-notes/$VERSION.md}"
OUTPUT_DIR="${RELEASE_NOTES_OUTPUT_DIR:-$ROOT/dist/release-notes}"
OUTPUT_PATH="${RELEASE_NOTES_PATH:-$OUTPUT_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER-$CHANNEL.md}"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ -f "$SOURCE_PATH" ]] || fail "Release notes source was not found: $SOURCE_PATH"
[[ -s "$SOURCE_PATH" ]] || fail "Release notes source is empty: $SOURCE_PATH"

mkdir -p "$OUTPUT_DIR"

{
    printf '# %s %s (%s)\n\n' "$APP_NAME" "$VERSION" "$BUILD_NUMBER"
    printf 'Channel: %s\n' "$CHANNEL"
    printf 'Release date: %s\n\n' "$(date -u +%Y-%m-%d)"
    cat "$SOURCE_PATH"
    printf '\n'
} > "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
