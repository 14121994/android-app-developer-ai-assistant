#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="${RELEASE_DIR:-}"
UPDATES_DIR="${UPDATES_DIR:-}"
HOSTING_DIR="${HOSTING_DIR:-}"
RSYNC_TARGET="${RSYNC_TARGET:-}"
CHANNEL="${CHANNEL:-stable}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
APPCAST_URL="${APPCAST_URL:-}"
PROMOTION_MANIFEST_PATH="${PROMOTION_MANIFEST_PATH:-}"
DRY_RUN="${DRY_RUN:-0}"

fail() {
    echo "error: $*" >&2
    exit 1
}

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "Required tool '$1' was not found."
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

json_bool() {
    if is_truthy "$1"; then
        printf 'true'
    else
        printf 'false'
    fi
}

copy_contents() {
    local source="$1"
    local destination="$2"
    mkdir -p "$destination"
    cp -R "$source"/. "$destination"/
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

require_inputs() {
    [[ -n "$RELEASE_DIR" ]] || fail "RELEASE_DIR is required."
    [[ -n "$UPDATES_DIR" ]] || fail "UPDATES_DIR is required."
    [[ -n "$HOSTING_DIR" ]] || fail "HOSTING_DIR is required."
    [[ -n "$CHANNEL" ]] || fail "CHANNEL is required."
    [[ -n "$VERSION" ]] || fail "VERSION is required."
    [[ -n "$BUILD_NUMBER" ]] || fail "BUILD_NUMBER is required."
    [[ -d "$RELEASE_DIR" ]] || fail "RELEASE_DIR does not exist: $RELEASE_DIR"
    [[ -d "$UPDATES_DIR" ]] || fail "UPDATES_DIR does not exist: $UPDATES_DIR"
    [[ -f "$UPDATES_DIR/appcast.xml" ]] || fail "Sparkle appcast is missing: $UPDATES_DIR/appcast.xml"
    find "$UPDATES_DIR" -maxdepth 1 -type f -name '*.zip' -print -quit | grep -q . \
        || fail "UPDATES_DIR must contain at least one Sparkle zip archive."
    require_tool shasum
}

stage_release() {
    local staging_dir="$1"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"

    cp "$UPDATES_DIR/appcast.xml" "$staging_dir/appcast.xml"
    find "$UPDATES_DIR" -maxdepth 1 -type f -name '*.zip' -exec cp {} "$staging_dir/" \;

    if [[ -f "$RELEASE_DIR/release-manifest.json" ]]; then
        cp "$RELEASE_DIR/release-manifest.json" "$staging_dir/release-manifest.json"
    fi
    if [[ -f "$RELEASE_DIR/artifact-verification.json" ]]; then
        cp "$RELEASE_DIR/artifact-verification.json" "$staging_dir/artifact-verification.json"
    fi
    find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.pkg' -exec cp {} "$staging_dir/" \;
}

verify_staged_release() {
    local staging_dir="$1"
    local archive_name
    archive_name="$(find "$staging_dir" -maxdepth 1 -type f -name '*.zip' -exec basename {} \; | sort | tail -n 1)"
    [[ -n "$archive_name" ]] || fail "No zip archive was staged."
    grep -Fq "$archive_name" "$staging_dir/appcast.xml" || fail "Staged appcast does not reference $archive_name."
}

sync_remote_if_needed() {
    local current_dir="$1"
    if [[ -z "$RSYNC_TARGET" ]]; then
        return
    fi

    require_tool rsync
    rsync -az --delete "$current_dir"/ "$RSYNC_TARGET"/
}

write_promotion_manifest() {
    local manifest_path="$1"
    local staging_dir="$2"
    local current_dir="$3"
    local snapshot_dir="$4"
    local dry_run="$5"
    local appcast_sha hosted_rollback_dir
    appcast_sha="$(sha256 "$staging_dir/appcast.xml")"
    hosted_rollback_dir=""
    if [[ -n "$snapshot_dir" ]]; then
        hosted_rollback_dir="$current_dir/_rollback/previous"
    fi

    mkdir -p "$(dirname "$manifest_path")"
    cat > "$manifest_path" <<JSON
{
  "status": "promoted",
  "dryRun": $(json_bool "$dry_run"),
  "promotedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "channel": "$(json_escape "$CHANNEL")",
  "version": "$(json_escape "$VERSION")",
  "buildNumber": "$(json_escape "$BUILD_NUMBER")",
  "appcastUrl": "$(json_escape "$APPCAST_URL")",
  "releaseDirectory": "$(json_escape "$RELEASE_DIR")",
  "updatesDirectory": "$(json_escape "$UPDATES_DIR")",
  "stagingDirectory": "$(json_escape "$staging_dir")",
  "currentDirectory": "$(json_escape "$current_dir")",
  "previousSnapshotDirectory": "$(json_escape "$snapshot_dir")",
  "hostedRollbackDirectory": "$(json_escape "$hosted_rollback_dir")",
  "rsyncTarget": "$(json_escape "$RSYNC_TARGET")",
  "appcastSHA256": "$(json_escape "$appcast_sha")"
}
JSON
}

main() {
    require_inputs

    local stamp staging_dir current_dir state_dir snapshot_dir next_dir manifest_path
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    staging_dir="$HOSTING_DIR/.staging/$CHANNEL/$VERSION-$BUILD_NUMBER"
    current_dir="$HOSTING_DIR/$CHANNEL"
    state_dir="$HOSTING_DIR/.release-state/$CHANNEL"
    snapshot_dir="$state_dir/previous-$stamp"
    next_dir="$HOSTING_DIR/.next-$CHANNEL-$VERSION-$BUILD_NUMBER-$$"
    manifest_path="${PROMOTION_MANIFEST_PATH:-$RELEASE_DIR/promotion-manifest.json}"

    stage_release "$staging_dir"
    verify_staged_release "$staging_dir"

    if is_truthy "$DRY_RUN"; then
        write_promotion_manifest "$manifest_path" "$staging_dir" "$current_dir" "$snapshot_dir" "$DRY_RUN"
        echo "Release promotion dry run staged at $staging_dir"
        return
    fi

    mkdir -p "$state_dir"
    rm -rf "$next_dir"
    mkdir -p "$next_dir"
    copy_contents "$staging_dir" "$next_dir"

    if [[ -d "$current_dir" ]]; then
        mv "$current_dir" "$snapshot_dir"
        printf '%s\n' "$snapshot_dir" > "$state_dir/latest-previous"
    else
        snapshot_dir=""
    fi

    if ! mv "$next_dir" "$current_dir"; then
        if [[ -n "$snapshot_dir" && -d "$snapshot_dir" ]]; then
            mv "$snapshot_dir" "$current_dir"
        fi
        fail "Could not promote staged release into $current_dir."
    fi

    if [[ -n "$snapshot_dir" && -d "$snapshot_dir" ]]; then
        rm -rf "$current_dir/_rollback/previous"
        mkdir -p "$current_dir/_rollback/previous"
        copy_contents "$snapshot_dir" "$current_dir/_rollback/previous"
        printf '%s\n' "$current_dir/_rollback/previous" > "$current_dir/_rollback/latest-previous"
    fi

    write_promotion_manifest "$manifest_path" "$staging_dir" "$current_dir" "$snapshot_dir" "$DRY_RUN"
    cp "$manifest_path" "$current_dir/promotion-manifest.json"
    sync_remote_if_needed "$current_dir"

    echo "Release promoted to $current_dir"
}

main "$@"
