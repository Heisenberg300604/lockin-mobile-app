#!/usr/bin/env bash
# Builds the Android app with the right build-time config every time.
#
#   scripts/build_android.sh            # dev keys, small per-CPU APKs (sideload/testing)
#   scripts/build_android.sh prod aab   # prod keys, app bundle for the Play Store
#
# Usage: scripts/build_android.sh [dev|prod] [apk|aab]
set -euo pipefail

cd "$(dirname "$0")/.."

env_name="${1:-dev}"
target="${2:-apk}"
env_file="env/${env_name}.json"

fail() { echo "error: $*" >&2; exit 1; }

[[ -f "$env_file" ]] || fail "$env_file not found. Copy env/dev.example.json to $env_file and fill it in."

# Without a real Clerk key the app builds fine but sign-in is silently disabled.
key=$(sed -n 's/.*"CLERK_PUBLISHABLE_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$env_file")
[[ "$key" == pk_test_* || "$key" == pk_live_* ]] || fail "CLERK_PUBLISHABLE_KEY in $env_file is missing or invalid."
[[ "$key" != *REPLACE_ME* ]] || fail "CLERK_PUBLISHABLE_KEY in $env_file is still the placeholder."

if [[ "$env_name" == "prod" ]]; then
  [[ "$key" == pk_live_* ]] || fail "prod builds must use a pk_live_ Clerk key."
  [[ -f android/key.properties ]] || fail "android/key.properties not found; prod builds must be signed with the upload key (docs/SETUP.md)."
fi

case "$target" in
  apk)
    # One APK per CPU type instead of one "fat" APK containing all three.
    flutter build apk --release --split-per-abi --dart-define-from-file="$env_file"
    echo
    echo "Install on a phone: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    ;;
  aab)
    flutter build appbundle --release --dart-define-from-file="$env_file"
    echo
    echo "Upload to Play Console: build/app/outputs/bundle/release/app-release.aab"
    ;;
  *) fail "unknown target '$target' (use apk or aab)" ;;
esac
