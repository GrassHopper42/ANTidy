#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ANTidy"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BINARY_PATH="${ROOT}/.build/${CONFIGURATION}/${APP_NAME}"
INFO_PLIST="${ROOT}/Packaging/Info.plist"
ENTITLEMENTS="${ROOT}/Packaging/ANTidy.entitlements"
ICON_FILE="${ROOT}/Packaging/ANTidy.icns"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

swift build -c "${CONFIGURATION}" --product "${APP_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
cp "${ICON_FILE}" "${RESOURCES_DIR}/${APP_NAME}.icns"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  codesign --force --sign - "${APP_DIR}"
  echo "Built ${APP_DIR} with ad-hoc signing."
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${SIGN_IDENTITY}" \
    "${APP_DIR}"
  echo "Built ${APP_DIR} signed with ${SIGN_IDENTITY}."
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
