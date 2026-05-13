#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Ascendancy"
PROJECT_FILE="$ROOT_DIR/Ascendancy.xcodeproj"
SCHEME="Ascendancy"
BUILD_DIR="$ROOT_DIR/build"
MARKETING_VERSION=$(grep "MARKETING_VERSION:" "$ROOT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/')
BUILD_VERSION=$(grep "CURRENT_PROJECT_VERSION:" "$ROOT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/')
APP_PATH="$BUILD_DIR/Release-iphoneos/$APP_NAME.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_NAME="${APP_NAME}_v${MARKETING_VERSION}_b${BUILD_VERSION}.ipa"
IPA_PATH="$BUILD_DIR/$IPA_NAME"

cleanup() {
  rm -rf "$PAYLOAD_DIR"
}

trap cleanup EXIT

xcodebuild clean build \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$BUILD_DIR"

mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"
rm -f "$IPA_PATH"

(cd "$BUILD_DIR" && zip -qr "$IPA_NAME" Payload)

printf 'Created %s\n' "$IPA_PATH"
