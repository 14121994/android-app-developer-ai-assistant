#!/usr/bin/env bash
set -euo pipefail

HOSTING_DIR="${HOSTING_DIR:-}"
CHANNEL="${CHANNEL:-stable}"
ROLLBACK_SOURCE="${ROLLBACK_SOURCE:-}"
RSYNC_TARGET="${RSYNC_TARGET:-}"
ROLLBACK_MANIFEST_PATH="${ROLLBACK_MANIFEST_PATH:-}"
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

resolve_rollback_source() {
    if [[ -n "$ROLLBACK_SOURCE" ]]; then
        printf '%s\n' "$ROLLBACK_SOURCE"
        return
    fi

    local pointer="$HOSTING_DIR/.release-state/$CHANNEL/latest-previous"
    if [[ -f "$pointer" ]]; then
        sed -n '1p' "$pointer"
        return
    fi

    local hosted_previous="$HOSTING_DIR/$CHANNEL/_rollback/previous"
    if [[ -d "$hosted_previous" ]]; then
        printf '%s\n' "$hosted_previous"
        return
    fi

    fail "No rollback source was provided and no previous release pointer exists: $pointer"
}

sync_remote_if_needed() {
    local current_dir="$1"
    if [[ -z "$RSYNC_TARGET" ]]; then
        return
    fi

    require_tool rsync
    rsync -az --delete "$current_dir"/ "$RSYNC_TARGET"/
}

write_rollback_manifest() {
    local manifest_path="$1"
    local source_dir="$2"
    local current_dir="$3"
    local replaced_snapshot_dir="$4"

    mkdir -p "$(dirname "$manifest_path")"
    cat > "$manifest_path" <<JSON
{
  "status": "rolledBack",
  "dryRun": $(json_bool "$DRY_RUN"),
  "rolledBackAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "channel": "$(json_escape "$CHANNEL")",
  "rollbackSourceDirectory": "$(json_escape "$source_dir")",
  "currentDirectory": "$(json_escape "$current_dir")",
  "replacedCurrentSnapshotDirectory": "$(json_escape "$replaced_snapshot_dir")",
  "rsyncTarget": "$(json_escape "$RSYNC_TARGET")"
}
JSON
}

main() {
    [[ -n "$HOSTING_DIR" ]] || fail "HOSTING_DIR is required."
    [[ -n "$CHANNEL" ]] || fail "CHANNEL is required."

    local source_dir current_dir state_dir replaced_snapshot_dir next_dir manifest_path stamp
    source_dir="$(resolve_rollback_source)"
    current_dir="$HOSTING_DIR/$CHANNEL"
    state_dir="$HOSTING_DIR/.release-state/$CHANNEL"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    replaced_snapshot_dir="$state_dir/rollback-replaced-$stamp"
    next_dir="$HOSTING_DIR/.rollback-next-$CHANNEL-$$"
    manifest_path="${ROLLBACK_MANIFEST_PATH:-$state_dir/rollback-$stamp.json}"

    [[ -d "$source_dir" ]] || fail "Rollback source does not exist: $source_dir"
    [[ -f "$source_dir/appcast.xml" ]] || fail "Rollback source is missing appcast.xml: $source_dir"
    find "$source_dir" -maxdepth 1 -type f -name '*.zip' -print -quit | grep -q . \
        || fail "Rollback source must contain at least one Sparkle zip archive."

    if is_truthy "$DRY_RUN"; then
        write_rollback_manifest "$manifest_path" "$source_dir" "$current_dir" "$replaced_snapshot_dir"
        echo "Release rollback dry run would restore $source_dir"
        return
    fi

    mkdir -p "$state_dir"
    rm -rf "$next_dir"
    mkdir -p "$next_dir"
    copy_contents "$source_dir" "$next_dir"

    if [[ -d "$current_dir" ]]; then
        mv "$current_dir" "$replaced_snapshot_dir"
    else
        replaced_snapshot_dir=""
    fi

    if ! mv "$next_dir" "$current_dir"; then
        if [[ -n "$replaced_snapshot_dir" && -d "$replaced_snapshot_dir" ]]; then
            mv "$replaced_snapshot_dir" "$current_dir"
        fi
        fail "Could not restore rollback source into $current_dir."
    fi

    sync_remote_if_needed "$current_dir"
    write_rollback_manifest "$manifest_path" "$source_dir" "$current_dir" "$replaced_snapshot_dir"
    cp "$manifest_path" "$current_dir/rollback-manifest.json"

    echo "Release rolled back to $source_dir"
}

main "$@"
