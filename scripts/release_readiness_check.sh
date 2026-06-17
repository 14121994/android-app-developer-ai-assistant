#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="${RELEASE:-0}"

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

require_value() {
    local name="$1"
    local value="${!name:-}"
    [[ -n "$value" ]] || fail "$name is required for a market launch release."
}

require_https_value() {
    local name="$1"
    local value="${!name:-}"
    require_value "$name"
    [[ "$value" == https://* ]] || fail "$name must be an HTTPS URL."
}

require_file_value() {
    local name="$1"
    local value="${!name:-}"
    require_value "$name"
    [[ -f "$value" ]] || fail "$name must point to an existing file: $value"
}

require_developer_id_identity() {
    local name="$1"
    local prefix="$2"
    local value="${!name:-}"
    require_value "$name"
    [[ "$value" == "$prefix"* ]] || fail "$name must start with '$prefix'."
}

if ! is_truthy "$RELEASE"; then
    echo "Market readiness gates skipped because RELEASE is not enabled."
    exit 0
fi

require_value BUNDLE_ID
[[ "$BUNDLE_ID" != com.example* ]] || fail "BUNDLE_ID must be owned by the distributing team, not com.example."

require_developer_id_identity SIGNING_IDENTITY "Developer ID Application:"
require_developer_id_identity INSTALLER_SIGNING_IDENTITY "Developer ID Installer:"
is_truthy "${NOTARIZE:-1}" || fail "NOTARIZE must be enabled for a market launch release."
if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    require_value APPLE_ID
    require_value APPLE_TEAM_ID
    require_value APPLE_APP_SPECIFIC_PASSWORD
fi

require_value SPARKLE_PUBLIC_ED_KEY
require_https_value APPCAST_URL
require_file_value SPARKLE_ROLLOUT_PLAN_PATH
require_file_value SPARKLE_ROLLBACK_PLAN_PATH

if is_truthy "${PROMOTE_RELEASE:-0}"; then
    require_value APPCAST_HOSTING_DIR
    if [[ "${APPCAST_HOSTING_DIR_EXPLICIT:-0}" != "1" && -z "${APPCAST_RSYNC_TARGET:-}" ]]; then
        fail "PROMOTE_RELEASE=1 requires an explicit APPCAST_HOSTING_DIR or APPCAST_RSYNC_TARGET."
    fi
fi

require_https_value LICENSE_ACTIVATION_URL
require_https_value LICENSE_REFRESH_URL
require_https_value LICENSE_RECOVERY_URL
require_https_value LICENSE_TRANSFER_URL
require_file_value LICENSE_POLICY_PATH

require_https_value PRIVACY_POLICY_URL
require_file_value DATA_RETENTION_POLICY_PATH
require_file_value SUPPORT_REDACTION_POLICY_PATH

require_https_value CRASH_REPORTING_ENDPOINT
require_https_value SUPPORT_UPLOAD_ENDPOINT
require_https_value SYMBOL_UPLOAD_ENDPOINT
require_file_value CRASH_PIPELINE_RUNBOOK_PATH

require_file_value ANDROID_MATRIX_REPORT_PATH

echo "Market readiness gates passed for $BUNDLE_ID."
