#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-}"
ZIP_PATH="${ZIP_PATH:-}"
PKG_PATH="${PKG_PATH:-}"
MANIFEST_PATH="${MANIFEST_PATH:-}"
APPCAST_PATH="${APPCAST_PATH:-}"
REPORT_PATH="${REPORT_PATH:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
REQUIRE_SPARKLE="${REQUIRE_SPARKLE:-0}"
VERIFY_EXTRACT_DIR=""

warnings=()

fail() {
    echo "error: $*" >&2
    exit 1
}

warn() {
    warnings+=("$*")
    echo "warning: $*" >&2
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

require_tool_if_needed() {
    local tool="$1"
    local required="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        return
    fi
    if is_truthy "$required"; then
        fail "Required release verification tool '$tool' was not found."
    fi
    warn "Skipping optional '$tool' verification because the tool was not found."
    return 1
}

require_dir() {
    local name="$1"
    local path="$2"
    [[ -n "$path" ]] || fail "$name was not provided."
    [[ -d "$path" ]] || fail "$name does not exist or is not a directory: $path"
}

require_file() {
    local name="$1"
    local path="$2"
    [[ -n "$path" ]] || fail "$name was not provided."
    [[ -f "$path" ]] || fail "$name does not exist: $path"
    [[ -s "$path" ]] || fail "$name is empty: $path"
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

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

verify_plist_metadata() {
    local plist="$APP_PATH/Contents/Info.plist"
    require_file "Info.plist" "$plist"

    local actual_bundle actual_version actual_build executable
    actual_bundle="$(plist_value "$plist" "CFBundleIdentifier")"
    actual_version="$(plist_value "$plist" "CFBundleShortVersionString")"
    actual_build="$(plist_value "$plist" "CFBundleVersion")"
    executable="$(plist_value "$plist" "CFBundleExecutable")"

    [[ -n "$actual_bundle" ]] || fail "Info.plist is missing CFBundleIdentifier."
    [[ -n "$actual_version" ]] || fail "Info.plist is missing CFBundleShortVersionString."
    [[ -n "$actual_build" ]] || fail "Info.plist is missing CFBundleVersion."
    [[ -n "$executable" ]] || fail "Info.plist is missing CFBundleExecutable."
    [[ -x "$APP_PATH/Contents/MacOS/$executable" ]] || fail "Bundle executable is missing or not executable: $executable"

    if [[ -n "$BUNDLE_ID" && "$actual_bundle" != "$BUNDLE_ID" ]]; then
        fail "Bundle identifier mismatch. Expected $BUNDLE_ID, got $actual_bundle."
    fi
    if [[ -n "$VERSION" && "$actual_version" != "$VERSION" ]]; then
        fail "Version mismatch. Expected $VERSION, got $actual_version."
    fi
    if [[ -n "$BUILD_NUMBER" && "$actual_build" != "$BUILD_NUMBER" ]]; then
        fail "Build number mismatch. Expected $BUILD_NUMBER, got $actual_build."
    fi
}

verify_codesigning() {
    require_tool_if_needed codesign "$REQUIRE_DEVELOPER_ID" || return
    if ! codesign --verify --strict --deep --verbose=2 "$APP_PATH" >/dev/null; then
        if is_truthy "$REQUIRE_DEVELOPER_ID"; then
            fail "App bundle code signature verification failed."
        fi
        warn "App bundle is not signed; skipping optional codesign verification."
        return
    fi

    if is_truthy "$REQUIRE_DEVELOPER_ID"; then
        codesign -dv "$APP_PATH" 2>&1 | grep -Fq "Authority=Developer ID Application:" \
            || fail "App bundle is not signed with a Developer ID Application identity."
    fi
}

verify_notarization() {
    if ! is_truthy "$REQUIRE_NOTARIZATION"; then
        return
    fi

    require_tool xcrun
    require_tool spctl
    xcrun stapler validate "$APP_PATH" >/dev/null
    xcrun stapler validate "$PKG_PATH" >/dev/null
    spctl --assess --type execute --verbose=4 "$APP_PATH" >/dev/null
    spctl --assess --type install --verbose=4 "$PKG_PATH" >/dev/null
}

verify_package_signature() {
    require_tool_if_needed pkgutil "$REQUIRE_DEVELOPER_ID" || return
    if ! pkgutil --check-signature "$PKG_PATH" >/dev/null; then
        if is_truthy "$REQUIRE_DEVELOPER_ID"; then
            fail "Installer package signature verification failed."
        fi
        warn "Installer package is not signed; skipping optional package signature verification."
        return
    fi
    if is_truthy "$REQUIRE_DEVELOPER_ID"; then
        pkgutil --check-signature "$PKG_PATH" 2>&1 | grep -Fq "Developer ID Installer:" \
            || fail "Installer package is not signed with a Developer ID Installer identity."
    fi
}

verify_zip_archive() {
    require_tool ditto
    local archive_app
    VERIFY_EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-dev-agent-verify.XXXXXX")"
    trap 'rm -rf "${VERIFY_EXTRACT_DIR:-}"' EXIT

    ditto -x -k "$ZIP_PATH" "$VERIFY_EXTRACT_DIR"
    archive_app="$(find "$VERIFY_EXTRACT_DIR" -maxdepth 2 -type d -name "$(basename "$APP_PATH")" -print | head -n 1)"
    [[ -n "$archive_app" ]] || fail "Zip archive does not contain $(basename "$APP_PATH")."

    if command -v codesign >/dev/null 2>&1; then
        if ! codesign --verify --strict --deep --verbose=2 "$archive_app" >/dev/null; then
            if is_truthy "$REQUIRE_DEVELOPER_ID"; then
                fail "Archived app code signature verification failed."
            fi
            warn "Archived app is not signed; skipping optional archived app codesign verification."
        fi
    fi
}

verify_appcast() {
    if [[ -z "$APPCAST_PATH" || ! -f "$APPCAST_PATH" ]]; then
        if is_truthy "$REQUIRE_SPARKLE"; then
            fail "Sparkle appcast was not found: ${APPCAST_PATH:-unset}"
        fi
        warn "Sparkle appcast was not found; skipping appcast verification."
        return
    fi

    local archive_name
    archive_name="$(basename "$ZIP_PATH")"
    grep -Fq "$archive_name" "$APPCAST_PATH" || fail "Appcast does not reference $archive_name."

    if is_truthy "$REQUIRE_SPARKLE"; then
        grep -Fq "sparkle:edSignature" "$APPCAST_PATH" || fail "Appcast is missing Sparkle EdDSA signatures."
        grep -Fq "sparkle:version=\"$BUILD_NUMBER\"" "$APPCAST_PATH" || warn "Appcast does not expose sparkle:version=\"$BUILD_NUMBER\"."
    fi
}

write_report() {
    if [[ -z "$REPORT_PATH" ]]; then
        return
    fi

    mkdir -p "$(dirname "$REPORT_PATH")"
    local warnings_json=""
    local warning
    for warning in "${warnings[@]}"; do
        if [[ -n "$warnings_json" ]]; then
            warnings_json+=", "
        fi
        warnings_json+="\"$(json_escape "$warning")\""
    done

    cat > "$REPORT_PATH" <<JSON
{
  "status": "verified",
  "verifiedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "bundleId": "$(json_escape "$BUNDLE_ID")",
  "version": "$(json_escape "$VERSION")",
  "buildNumber": "$(json_escape "$BUILD_NUMBER")",
  "appPath": "$(json_escape "$APP_PATH")",
  "zipPath": "$(json_escape "$ZIP_PATH")",
  "pkgPath": "$(json_escape "$PKG_PATH")",
  "manifestPath": "$(json_escape "$MANIFEST_PATH")",
  "appcastPath": "$(json_escape "$APPCAST_PATH")",
  "zipSHA256": "$(json_escape "$(sha256 "$ZIP_PATH")")",
  "pkgSHA256": "$(json_escape "$(sha256 "$PKG_PATH")")",
  "zipBytes": $(file_size "$ZIP_PATH"),
  "pkgBytes": $(file_size "$PKG_PATH"),
  "developerIdRequired": $(json_bool "$REQUIRE_DEVELOPER_ID"),
  "notarizationRequired": $(json_bool "$REQUIRE_NOTARIZATION"),
  "sparkleRequired": $(json_bool "$REQUIRE_SPARKLE"),
  "warnings": [$warnings_json]
}
JSON
}

main() {
    require_dir "APP_PATH" "$APP_PATH"
    require_file "ZIP_PATH" "$ZIP_PATH"
    require_file "PKG_PATH" "$PKG_PATH"
    require_file "MANIFEST_PATH" "$MANIFEST_PATH"
    require_tool shasum

    verify_plist_metadata
    verify_codesigning
    verify_package_signature
    verify_zip_archive
    verify_appcast
    verify_notarization
    write_report

    echo "Release artifacts verified: $REPORT_PATH"
}

main "$@"
