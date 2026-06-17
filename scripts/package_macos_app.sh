#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$ROOT/packaging/macos"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"

APP_NAME="${APP_NAME:-Android Dev Agent}"
APP_BUNDLE_NAME="$APP_NAME.app"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-AndroidDevAgent}"
BUNDLE_ID_WAS_SET="${BUNDLE_ID+x}"
BUNDLE_ID="${BUNDLE_ID:-com.akshaykamat.androiddevagent}"
APP_CATEGORY="${APP_CATEGORY:-public.app-category.developer-tools}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CHANNEL="${CHANNEL:-stable}"
COPYRIGHT="${COPYRIGHT:-Copyright (c) 2026 Akshay Kamat. All rights reserved.}"

RELEASE="${RELEASE:-0}"
MARKET_READINESS_CHECK="${MARKET_READINESS_CHECK:-$RELEASE}"
ALLOW_AD_HOC_SIGNING="${ALLOW_AD_HOC_SIGNING:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
INSTALLER_SIGNING_IDENTITY="${INSTALLER_SIGNING_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$PACKAGING_DIR/AndroidDevAgent.entitlements}"
NOTARIZE="${NOTARIZE:-$RELEASE}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
LICENSE_ACTIVATION_URL="${LICENSE_ACTIVATION_URL:-}"
LICENSE_REFRESH_URL="${LICENSE_REFRESH_URL:-}"
LICENSE_RECOVERY_URL="${LICENSE_RECOVERY_URL:-}"
LICENSE_TRANSFER_URL="${LICENSE_TRANSFER_URL:-}"
PRIVACY_POLICY_URL="${PRIVACY_POLICY_URL:-}"
CRASH_REPORTING_ENDPOINT="${CRASH_REPORTING_ENDPOINT:-}"
SUPPORT_UPLOAD_ENDPOINT="${SUPPORT_UPLOAD_ENDPOINT:-}"
SYMBOL_UPLOAD_ENDPOINT="${SYMBOL_UPLOAD_ENDPOINT:-}"
DSYM_UUID="${DSYM_UUID:-}"

SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
UPDATE_BASE_URL_WAS_SET="${UPDATE_BASE_URL+x}"
APPCAST_URL_WAS_SET="${APPCAST_URL+x}"
UPDATE_BASE_URL="${UPDATE_BASE_URL:-https://updates.androiddevagent.app/$CHANNEL}"
APPCAST_URL="${APPCAST_URL:-$UPDATE_BASE_URL/appcast.xml}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"

APP_PATH="${APP_PATH:-$DIST_DIR/$APP_BUNDLE_NAME}"
RELEASE_DIR="${RELEASE_DIR:-$DIST_DIR/release/$CHANNEL/$VERSION-$BUILD_NUMBER}"
UPDATES_DIR="${UPDATES_DIR:-$DIST_DIR/updates/$CHANNEL}"
APP_ARCHIVE_NAME="${APP_ARCHIVE_NAME:-AndroidDevAgent-$VERSION-$BUILD_NUMBER-$CHANNEL.zip}"
PKG_NAME="${PKG_NAME:-AndroidDevAgent-$VERSION-$BUILD_NUMBER-$CHANNEL.pkg}"
APP_ARCHIVE_PATH="$RELEASE_DIR/$APP_ARCHIVE_NAME"
PKG_PATH="$RELEASE_DIR/$PKG_NAME"
MANIFEST_PATH="$RELEASE_DIR/release-manifest.json"
RELEASE_NOTES_SOURCE="${RELEASE_NOTES_SOURCE:-$ROOT/release-notes/$VERSION.md}"
RELEASE_NOTES_PATH="${RELEASE_NOTES_PATH:-$RELEASE_DIR/RELEASE_NOTES.md}"
APPCAST_PATH="$UPDATES_DIR/appcast.xml"
VERIFY_RELEASE_ARTIFACTS="${VERIFY_RELEASE_ARTIFACTS:-1}"
ARTIFACT_VERIFICATION_REPORT_PATH="${ARTIFACT_VERIFICATION_REPORT_PATH:-$RELEASE_DIR/artifact-verification.json}"
PROMOTE_RELEASE="${PROMOTE_RELEASE:-0}"
APPCAST_HOSTING_DIR_WAS_SET="${APPCAST_HOSTING_DIR+x}"
APPCAST_HOSTING_DIR="${APPCAST_HOSTING_DIR:-$DIST_DIR/appcast-hosting}"
APPCAST_RSYNC_TARGET="${APPCAST_RSYNC_TARGET:-}"
PROMOTION_MANIFEST_PATH="${PROMOTION_MANIFEST_PATH:-$RELEASE_DIR/promotion-manifest.json}"

fail() {
    echo "error: $*" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "Required tool '$1' was not found."
}

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&apos;}"
    printf '%s' "$value"
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

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

validate_release_configuration() {
    [[ "$BUNDLE_ID" != com.example* ]] || fail "BUNDLE_ID must not use the com.example namespace."
    [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || fail "BUNDLE_ID '$BUNDLE_ID' is not a valid reverse-DNS identifier."
    [[ "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+)*$ ]] || fail "BUILD_NUMBER must use dot-separated integers for CFBundleVersion."

    if is_truthy "$RELEASE"; then
        [[ -n "$BUNDLE_ID_WAS_SET" ]] || fail "RELEASE=1 requires an explicit BUNDLE_ID owned by the distributing team."
        [[ -n "$SIGNING_IDENTITY" ]] || fail "RELEASE=1 requires SIGNING_IDENTITY, usually 'Developer ID Application: ...'."
        [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]] || fail "RELEASE=1 requires a Developer ID Application signing identity."
        [[ -n "$INSTALLER_SIGNING_IDENTITY" ]] || fail "RELEASE=1 requires INSTALLER_SIGNING_IDENTITY, usually 'Developer ID Installer: ...'."
        [[ "$INSTALLER_SIGNING_IDENTITY" == Developer\ ID\ Installer:* ]] || fail "RELEASE=1 requires a Developer ID Installer signing identity."
        [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]] || fail "RELEASE=1 requires SPARKLE_PUBLIC_ED_KEY from Sparkle's generate_keys tool."
        [[ -n "$UPDATE_BASE_URL_WAS_SET" || -n "$APPCAST_URL_WAS_SET" ]] || fail "RELEASE=1 requires UPDATE_BASE_URL or APPCAST_URL for the published Sparkle feed."
        [[ "$APPCAST_URL" == https://* ]] || fail "RELEASE=1 requires an HTTPS APPCAST_URL."
        [[ -f "$RELEASE_NOTES_SOURCE" ]] || fail "RELEASE=1 requires release notes at RELEASE_NOTES_SOURCE or release-notes/$VERSION.md."
        if is_truthy "$NOTARIZE"; then
            if [[ -z "$NOTARYTOOL_PROFILE" ]]; then
                [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_APP_SPECIFIC_PASSWORD" ]] \
                    || fail "NOTARIZE=1 requires NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD."
            fi
        fi
    fi
}

run_market_readiness_check() {
    if ! is_truthy "$RELEASE" || ! is_truthy "$MARKET_READINESS_CHECK"; then
        return
    fi

    RELEASE="$RELEASE" \
    BUNDLE_ID="$BUNDLE_ID" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" \
    INSTALLER_SIGNING_IDENTITY="$INSTALLER_SIGNING_IDENTITY" \
    NOTARIZE="$NOTARIZE" \
    NOTARYTOOL_PROFILE="$NOTARYTOOL_PROFILE" \
    APPLE_ID="$APPLE_ID" \
    APPLE_TEAM_ID="$APPLE_TEAM_ID" \
    APPLE_APP_SPECIFIC_PASSWORD="$APPLE_APP_SPECIFIC_PASSWORD" \
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
    APPCAST_URL="$APPCAST_URL" \
    APPCAST_HOSTING_DIR="${APPCAST_HOSTING_DIR:-}" \
    APPCAST_HOSTING_DIR_EXPLICIT="${APPCAST_HOSTING_DIR_WAS_SET:+1}" \
    APPCAST_RSYNC_TARGET="${APPCAST_RSYNC_TARGET:-}" \
    PROMOTE_RELEASE="$PROMOTE_RELEASE" \
    SPARKLE_ROLLOUT_PLAN_PATH="${SPARKLE_ROLLOUT_PLAN_PATH:-}" \
    SPARKLE_ROLLBACK_PLAN_PATH="${SPARKLE_ROLLBACK_PLAN_PATH:-}" \
    LICENSE_ACTIVATION_URL="${LICENSE_ACTIVATION_URL:-}" \
    LICENSE_REFRESH_URL="${LICENSE_REFRESH_URL:-}" \
    LICENSE_RECOVERY_URL="${LICENSE_RECOVERY_URL:-}" \
    LICENSE_TRANSFER_URL="${LICENSE_TRANSFER_URL:-}" \
    LICENSE_POLICY_PATH="${LICENSE_POLICY_PATH:-}" \
    PRIVACY_POLICY_URL="${PRIVACY_POLICY_URL:-}" \
    DATA_RETENTION_POLICY_PATH="${DATA_RETENTION_POLICY_PATH:-}" \
    SUPPORT_REDACTION_POLICY_PATH="${SUPPORT_REDACTION_POLICY_PATH:-}" \
    CRASH_REPORTING_ENDPOINT="${CRASH_REPORTING_ENDPOINT:-}" \
    SUPPORT_UPLOAD_ENDPOINT="${SUPPORT_UPLOAD_ENDPOINT:-}" \
    SYMBOL_UPLOAD_ENDPOINT="${SYMBOL_UPLOAD_ENDPOINT:-}" \
    CRASH_PIPELINE_RUNBOOK_PATH="${CRASH_PIPELINE_RUNBOOK_PATH:-}" \
    ANDROID_MATRIX_REPORT_PATH="${ANDROID_MATRIX_REPORT_PATH:-}" \
        "$ROOT/scripts/release_readiness_check.sh"
}

write_info_plist() {
    local plist_path="$1"
    local escaped_app_name escaped_bundle_id escaped_version escaped_build escaped_category escaped_min_os escaped_copyright
    escaped_app_name="$(xml_escape "$APP_NAME")"
    escaped_bundle_id="$(xml_escape "$BUNDLE_ID")"
    escaped_version="$(xml_escape "$VERSION")"
    escaped_build="$(xml_escape "$BUILD_NUMBER")"
    escaped_category="$(xml_escape "$APP_CATEGORY")"
    escaped_min_os="$(xml_escape "$MINIMUM_SYSTEM_VERSION")"
    escaped_copyright="$(xml_escape "$COPYRIGHT")"

    cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$escaped_app_name</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AndroidDevAgent</string>
    <key>CFBundleIdentifier</key>
    <string>$escaped_bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$escaped_app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$escaped_version</string>
    <key>CFBundleVersion</key>
    <string>$escaped_build</string>
    <key>LSApplicationCategoryType</key>
    <string>$escaped_category</string>
    <key>LSMinimumSystemVersion</key>
    <string>$escaped_min_os</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>$escaped_copyright</string>
    <key>AndroidDevAgentReleaseNotesResource</key>
    <string>RELEASE_NOTES.md</string>
PLIST

    if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        local escaped_appcast escaped_public_key
        escaped_appcast="$(xml_escape "$APPCAST_URL")"
        escaped_public_key="$(xml_escape "$SPARKLE_PUBLIC_ED_KEY")"
        cat >> "$plist_path" <<PLIST
    <key>SUFeedURL</key>
    <string>$escaped_appcast</string>
    <key>SUPublicEDKey</key>
    <string>$escaped_public_key</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
PLIST
    fi

    if [[ -n "$LICENSE_ACTIVATION_URL" ]]; then
        local escaped_license_activation_url
        escaped_license_activation_url="$(xml_escape "$LICENSE_ACTIVATION_URL")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentLicenseActivationURL</key>
    <string>$escaped_license_activation_url</string>
PLIST
    fi

    if [[ -n "$LICENSE_REFRESH_URL" ]]; then
        local escaped_license_refresh_url
        escaped_license_refresh_url="$(xml_escape "$LICENSE_REFRESH_URL")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentLicenseRefreshURL</key>
    <string>$escaped_license_refresh_url</string>
PLIST
    fi

    if [[ -n "$LICENSE_RECOVERY_URL" ]]; then
        local escaped_license_recovery_url
        escaped_license_recovery_url="$(xml_escape "$LICENSE_RECOVERY_URL")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentLicenseRecoveryURL</key>
    <string>$escaped_license_recovery_url</string>
PLIST
    fi

    if [[ -n "$LICENSE_TRANSFER_URL" ]]; then
        local escaped_license_transfer_url
        escaped_license_transfer_url="$(xml_escape "$LICENSE_TRANSFER_URL")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentLicenseTransferURL</key>
    <string>$escaped_license_transfer_url</string>
PLIST
    fi

    if [[ -n "$PRIVACY_POLICY_URL" ]]; then
        local escaped_privacy_policy_url
        escaped_privacy_policy_url="$(xml_escape "$PRIVACY_POLICY_URL")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentPrivacyPolicyURL</key>
    <string>$escaped_privacy_policy_url</string>
PLIST
    fi

    if [[ -n "$CRASH_REPORTING_ENDPOINT" ]]; then
        local escaped_crash_reporting_endpoint
        escaped_crash_reporting_endpoint="$(xml_escape "$CRASH_REPORTING_ENDPOINT")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentCrashReportingEndpoint</key>
    <string>$escaped_crash_reporting_endpoint</string>
PLIST
    fi

    if [[ -n "$SUPPORT_UPLOAD_ENDPOINT" ]]; then
        local escaped_support_upload_endpoint
        escaped_support_upload_endpoint="$(xml_escape "$SUPPORT_UPLOAD_ENDPOINT")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentSupportUploadEndpoint</key>
    <string>$escaped_support_upload_endpoint</string>
PLIST
    fi

    if [[ -n "$SYMBOL_UPLOAD_ENDPOINT" ]]; then
        local escaped_symbol_upload_endpoint
        escaped_symbol_upload_endpoint="$(xml_escape "$SYMBOL_UPLOAD_ENDPOINT")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentSymbolUploadEndpoint</key>
    <string>$escaped_symbol_upload_endpoint</string>
PLIST
    fi

    if [[ -n "$DSYM_UUID" ]]; then
        local escaped_dsym_uuid
        escaped_dsym_uuid="$(xml_escape "$DSYM_UUID")"
        cat >> "$plist_path" <<PLIST
    <key>AndroidDevAgentDSYMUUID</key>
    <string>$escaped_dsym_uuid</string>
PLIST
    fi

    cat >> "$plist_path" <<PLIST
</dict>
</plist>
PLIST
}

generate_icon() {
    local resources_dir="$1"
    local iconset_dir="$RELEASE_DIR/AndroidDevAgent.iconset"

    require_tool python3
    require_tool iconutil

    rm -rf "$iconset_dir"
    python3 "$PACKAGING_DIR/generate_app_icon.py" "$iconset_dir"
    iconutil -c icns "$iconset_dir" -o "$resources_dir/AndroidDevAgent.icns"
}

find_sparkle_framework() {
    find "$ROOT/.build" \
        -path "*/Sparkle.framework" \
        -type d \
        -print \
        2>/dev/null \
        | sort \
        | head -n 1
}

embed_sparkle_framework() {
    local frameworks_dir="$1"
    local framework_path
    framework_path="$(find_sparkle_framework)"
    [[ -n "$framework_path" ]] || fail "Sparkle.framework was not found under .build. Run swift build after resolving dependencies."

    mkdir -p "$frameworks_dir"
    ditto "$framework_path" "$frameworks_dir/Sparkle.framework"
}

ensure_framework_rpath() {
    local executable_path="$1"
    if ! otool -l "$executable_path" | grep -Fq "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$executable_path"
    fi
}

sign_path() {
    local path="$1"
    local identity="$2"
    shift 2
    local args=(--force --sign "$identity")
    if [[ "$identity" != "-" ]]; then
        args+=(--timestamp --options runtime)
    fi
    args+=("$@")
    args+=("$path")
    codesign "${args[@]}"
}

sign_app_bundle() {
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        if is_truthy "$ALLOW_AD_HOC_SIGNING"; then
            SIGNING_IDENTITY="-"
            echo "warning: using ad-hoc signing because ALLOW_AD_HOC_SIGNING=1. Do not ship this build." >&2
        else
            echo "warning: app bundle is unsigned. Set SIGNING_IDENTITY for Developer ID distribution." >&2
            return
        fi
    fi

    require_tool codesign

    if [[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
        sign_path "$APP_PATH/Contents/Frameworks/Sparkle.framework" "$SIGNING_IDENTITY" --deep
    fi

    local app_sign_args=()
    if [[ "$SIGNING_IDENTITY" != "-" && -f "$ENTITLEMENTS_PATH" ]]; then
        app_sign_args+=(--entitlements "$ENTITLEMENTS_PATH")
    fi
    sign_path "$APP_PATH" "$SIGNING_IDENTITY" "${app_sign_args[@]}"
    codesign --verify --strict --deep --verbose=2 "$APP_PATH"
}

build_app_bundle() {
    local executable="$ROOT/.build/$BUILD_CONFIGURATION/$EXECUTABLE_NAME"
    local contents_dir="$APP_PATH/Contents"
    local macos_dir="$contents_dir/MacOS"
    local resources_dir="$contents_dir/Resources"
    local frameworks_dir="$contents_dir/Frameworks"

    swift build -c "$BUILD_CONFIGURATION" --package-path "$ROOT"
    [[ -x "$executable" ]] || fail "Expected executable was not built at $executable."

    rm -rf "$APP_PATH"
    mkdir -p "$macos_dir" "$resources_dir" "$frameworks_dir" "$RELEASE_DIR" "$UPDATES_DIR"
    cp "$executable" "$macos_dir/$EXECUTABLE_NAME"
    chmod +x "$macos_dir/$EXECUTABLE_NAME"

    write_info_plist "$contents_dir/Info.plist"
    generate_icon "$resources_dir"
    cp "$RELEASE_NOTES_PATH" "$resources_dir/RELEASE_NOTES.md"
    embed_sparkle_framework "$frameworks_dir"
    ensure_framework_rpath "$macos_dir/$EXECUTABLE_NAME"
    xattr -cr "$APP_PATH" 2>/dev/null || true
    touch "$APP_PATH"
    sign_app_bundle
}

build_zip_archive() {
    rm -f "$APP_ARCHIVE_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ARCHIVE_PATH"
    cp "$APP_ARCHIVE_PATH" "$UPDATES_DIR/$APP_ARCHIVE_NAME"
}

build_installer_package() {
    require_tool pkgbuild
    require_tool productbuild

    local pkg_root="$RELEASE_DIR/pkgroot"
    local component_pkg="$RELEASE_DIR/$EXECUTABLE_NAME-component.pkg"
    rm -rf "$pkg_root" "$component_pkg" "$PKG_PATH"
    mkdir -p "$pkg_root/Applications"
    ditto "$APP_PATH" "$pkg_root/Applications/$APP_BUNDLE_NAME"

    pkgbuild \
        --root "$pkg_root" \
        --identifier "$BUNDLE_ID.pkg" \
        --version "$VERSION" \
        --install-location "/" \
        "$component_pkg"

    local productbuild_args=(--package "$component_pkg")
    if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
        productbuild_args=(--sign "$INSTALLER_SIGNING_IDENTITY" "${productbuild_args[@]}")
    else
        echo "warning: installer package is unsigned. Set INSTALLER_SIGNING_IDENTITY for Developer ID distribution." >&2
    fi
    productbuild "${productbuild_args[@]}" "$PKG_PATH"
}

notarize_artifact() {
    local artifact="$1"
    local staple_target="$2"
    local args=()
    if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
        args=(--keychain-profile "$NOTARYTOOL_PROFILE")
    else
        args=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
    fi
    xcrun notarytool submit "$artifact" "${args[@]}" --wait
    xcrun stapler staple "$staple_target"
}

run_notarization() {
    if ! is_truthy "$NOTARIZE"; then
        return
    fi

    require_tool xcrun
    notarize_artifact "$APP_ARCHIVE_PATH" "$APP_PATH"
    notarize_artifact "$PKG_PATH" "$PKG_PATH"
    build_zip_archive
}

find_generate_appcast() {
    if [[ -n "$SPARKLE_GENERATE_APPCAST" ]]; then
        printf '%s\n' "$SPARKLE_GENERATE_APPCAST"
        return
    fi

    find "$ROOT/.build" \
        -path "*/generate_appcast" \
        -type f \
        -perm -111 \
        -print \
        2>/dev/null \
        | sort \
        | head -n 1
}

generate_appcast() {
    if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        if is_truthy "$RELEASE"; then
            fail "RELEASE=1 requires SPARKLE_PUBLIC_ED_KEY before appcast generation."
        fi
        echo "warning: SPARKLE_PUBLIC_ED_KEY is not set; appcast generation skipped." >&2
        return
    fi

    local tool
    tool="$(find_generate_appcast)"
    if [[ -z "$tool" ]]; then
        if is_truthy "$RELEASE"; then
            fail "Sparkle generate_appcast was not found; release appcast generation cannot continue."
        fi
        echo "warning: Sparkle generate_appcast was not found; appcast generation skipped." >&2
        return
    fi

    "$tool" "$UPDATES_DIR"
}

generate_release_notes() {
    RELEASE_NOTES_OUTPUT_DIR="$RELEASE_DIR" \
    RELEASE_NOTES_PATH="$RELEASE_NOTES_PATH" \
    RELEASE_NOTES_SOURCE="$RELEASE_NOTES_SOURCE" \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    CHANNEL="$CHANNEL" \
    APP_NAME="$APP_NAME" \
        "$ROOT/scripts/generate_release_notes.sh" >/dev/null
}

write_release_manifest() {
    local signed notarized sparkle_enabled promoted zip_sha pkg_sha app_sha zip_size pkg_size
    signed=false
    notarized=false
    sparkle_enabled=false
    promoted=false
    [[ -n "$SIGNING_IDENTITY" ]] && signed=true
    is_truthy "$NOTARIZE" && notarized=true
    [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]] && sparkle_enabled=true
    is_truthy "$PROMOTE_RELEASE" && promoted=true
    zip_sha="$(sha256_or_empty "$APP_ARCHIVE_PATH")"
    pkg_sha="$(sha256_or_empty "$PKG_PATH")"
    app_sha="$(bundle_content_digest_or_empty "$APP_PATH")"
    zip_size="$(file_size_or_zero "$APP_ARCHIVE_PATH")"
    pkg_size="$(file_size_or_zero "$PKG_PATH")"

    cat > "$MANIFEST_PATH" <<JSON
{
  "appName": "$(json_escape "$APP_NAME")",
  "bundleId": "$(json_escape "$BUNDLE_ID")",
  "version": "$(json_escape "$VERSION")",
  "buildNumber": "$(json_escape "$BUILD_NUMBER")",
  "channel": "$(json_escape "$CHANNEL")",
  "minimumSystemVersion": "$(json_escape "$MINIMUM_SYSTEM_VERSION")",
  "appPath": "$(json_escape "$APP_PATH")",
  "zipPath": "$(json_escape "$APP_ARCHIVE_PATH")",
  "pkgPath": "$(json_escape "$PKG_PATH")",
  "releaseNotesPath": "$(json_escape "$RELEASE_NOTES_PATH")",
  "appcastUrl": "$(json_escape "$APPCAST_URL")",
  "appcastPath": "$(json_escape "$APPCAST_PATH")",
  "artifactVerificationReportPath": "$(json_escape "$ARTIFACT_VERIFICATION_REPORT_PATH")",
  "promotionManifestPath": "$(json_escape "$PROMOTION_MANIFEST_PATH")",
  "licenseActivationUrl": "$(json_escape "$LICENSE_ACTIVATION_URL")",
  "licenseRefreshUrl": "$(json_escape "$LICENSE_REFRESH_URL")",
  "licenseRecoveryUrl": "$(json_escape "$LICENSE_RECOVERY_URL")",
  "licenseTransferUrl": "$(json_escape "$LICENSE_TRANSFER_URL")",
  "privacyPolicyUrl": "$(json_escape "$PRIVACY_POLICY_URL")",
  "crashReportingEndpoint": "$(json_escape "$CRASH_REPORTING_ENDPOINT")",
  "supportUploadEndpoint": "$(json_escape "$SUPPORT_UPLOAD_ENDPOINT")",
  "symbolUploadEndpoint": "$(json_escape "$SYMBOL_UPLOAD_ENDPOINT")",
  "dSYMUUID": "$(json_escape "$DSYM_UUID")",
  "updatesDirectory": "$(json_escape "$UPDATES_DIR")",
  "appcastHostingDirectory": "$(json_escape "$APPCAST_HOSTING_DIR")",
  "zipSHA256": "$(json_escape "$zip_sha")",
  "pkgSHA256": "$(json_escape "$pkg_sha")",
  "appBundleContentSHA256": "$(json_escape "$app_sha")",
  "zipBytes": $zip_size,
  "pkgBytes": $pkg_size,
  "developerIdSigned": $signed,
  "notarized": $notarized,
  "sparkleEnabled": $sparkle_enabled,
  "promoted": $promoted
}
JSON
}

sha256_or_empty() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    shasum -a 256 "$path" | awk '{print $1}'
}

bundle_content_digest_or_empty() {
    local path="$1"
    [[ -d "$path" ]] || return 0
    find "$path" -type f -print \
        | LC_ALL=C sort \
        | while IFS= read -r file_path; do
            shasum -a 256 "$file_path"
        done \
        | shasum -a 256 \
        | awk '{print $1}'
}

file_size_or_zero() {
    local path="$1"
    [[ -f "$path" ]] || {
        printf '0'
        return
    }
    wc -c < "$path" | tr -d '[:space:]'
}

run_artifact_verification() {
    if ! is_truthy "$VERIFY_RELEASE_ARTIFACTS"; then
        return
    fi

    RELEASE="$RELEASE" \
    APP_PATH="$APP_PATH" \
    ZIP_PATH="$APP_ARCHIVE_PATH" \
    PKG_PATH="$PKG_PATH" \
    MANIFEST_PATH="$MANIFEST_PATH" \
    APPCAST_PATH="$APPCAST_PATH" \
    REPORT_PATH="$ARTIFACT_VERIFICATION_REPORT_PATH" \
    BUNDLE_ID="$BUNDLE_ID" \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    REQUIRE_DEVELOPER_ID="$RELEASE" \
    REQUIRE_NOTARIZATION="$NOTARIZE" \
    REQUIRE_SPARKLE="$RELEASE" \
        "$ROOT/scripts/verify_release_artifacts.sh"
}

promote_release() {
    if ! is_truthy "$PROMOTE_RELEASE"; then
        return
    fi

    RELEASE_DIR="$RELEASE_DIR" \
    UPDATES_DIR="$UPDATES_DIR" \
    HOSTING_DIR="$APPCAST_HOSTING_DIR" \
    RSYNC_TARGET="$APPCAST_RSYNC_TARGET" \
    CHANNEL="$CHANNEL" \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    APPCAST_URL="$APPCAST_URL" \
    PROMOTION_MANIFEST_PATH="$PROMOTION_MANIFEST_PATH" \
        "$ROOT/scripts/promote_release.sh"
}

main() {
    require_tool swift
    require_tool ditto
    require_tool otool
    require_tool install_name_tool

    validate_release_configuration
    run_market_readiness_check
    generate_release_notes
    build_app_bundle
    build_zip_archive
    build_installer_package
    run_notarization
    generate_appcast
    write_release_manifest
    run_artifact_verification
    promote_release

    echo "App: $APP_PATH"
    echo "Zip: $APP_ARCHIVE_PATH"
    echo "Pkg: $PKG_PATH"
    echo "Release Notes: $RELEASE_NOTES_PATH"
    echo "Manifest: $MANIFEST_PATH"
    echo "Verification: $ARTIFACT_VERIFICATION_REPORT_PATH"
    if is_truthy "$PROMOTE_RELEASE"; then
        echo "Promotion: $PROMOTION_MANIFEST_PATH"
    fi
}

main "$@"
