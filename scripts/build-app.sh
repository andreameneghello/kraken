#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="Kraken"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"

echo "Building release binary..."
swift build -c release

echo "Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "scripts/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "Built ${APP_BUNDLE}"
