#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build-package}"
DIST_DIR="${DIST_DIR:-${SCRIPT_DIR}/dist}"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
SANDBOX_HOME_DIR="${BUILD_DIR}/packaging-home"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
INCLUDE_KINECT_V1_FIRMWARE="${INCLUDE_KINECT_V1_FIRMWARE:-0}"

find_tool() {
  local explicit_path="$1"
  shift
  if [[ -n "${explicit_path}" && -x "${explicit_path}" ]]; then
    printf '%s\n' "${explicit_path}"
    return 0
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

CMAKE_BIN="$(find_tool "${CMAKE_BIN:-}" "$(command -v cmake 2>/dev/null || true)" /opt/homebrew/bin/cmake /usr/local/bin/cmake)"
NINJA_BIN="$(find_tool "${NINJA_BIN:-}" "$(command -v ninja 2>/dev/null || true)" /opt/homebrew/bin/ninja /usr/local/bin/ninja || true)"

if [[ -z "${CMAKE_BIN}" ]]; then
  echo "CMake not found. Set CMAKE_BIN or add CMake to PATH." >&2
  exit 1
fi

APP_VERSION="1.0.0"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
APP_BUNDLE="${BUILD_DIR}/macKinect.app"
ZIP_PATH="${DIST_DIR}/macKinect-${APP_VERSION}-${STAMP}.zip"
DMG_PATH="${DIST_DIR}/macKinect-${APP_VERSION}-${STAMP}.dmg"
CHECKSUM_PATH="${DIST_DIR}/macKinect-${APP_VERSION}-${STAMP}.sha256.txt"
STAGING_DIR="${DIST_DIR}/macKinect-${APP_VERSION}-${STAMP}"
STAGING_DOCS_DIR="${STAGING_DIR}/Documentation"
STAGING_LICENSES_DIR="${STAGING_DIR}/Licenses"
STAGING_APP_BUNDLE="${STAGING_DIR}/macKinect.app"

mkdir -p "${MODULE_CACHE_DIR}" "${SANDBOX_HOME_DIR}" "${DIST_DIR}"

if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
  CACHE_SOURCE_DIR="$(awk -F= '/^CMAKE_HOME_DIRECTORY:INTERNAL=/{print $2; exit}' "${BUILD_DIR}/CMakeCache.txt")"
  if [[ -n "${CACHE_SOURCE_DIR}" && "${CACHE_SOURCE_DIR}" != "${SCRIPT_DIR}" ]]; then
    echo "Clearing stale packaging build directory: ${BUILD_DIR}"
    find "${BUILD_DIR}" -mindepth 1 -depth -delete
  fi
fi

if [[ -f "${SCRIPT_DIR}/VERSION" && -f "${BUILD_DIR}/macKinect.app/Contents/Info.plist" && "${SCRIPT_DIR}/VERSION" -nt "${BUILD_DIR}/macKinect.app/Contents/Info.plist" ]]; then
  echo "Clearing packaging build directory because version metadata changed: ${BUILD_DIR}"
  find "${BUILD_DIR}" -mindepth 1 -depth -delete
fi

mkdir -p "${BUILD_DIR}"

CONFIGURE_ARGS=(
  -S "${SCRIPT_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_BUILD_TYPE=Release
)
if [[ -n "${NINJA_BIN}" ]]; then
  CONFIGURE_ARGS+=(-G Ninja "-DCMAKE_MAKE_PROGRAM=${NINJA_BIN}")
fi

env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  "${CMAKE_BIN}" "${CONFIGURE_ARGS[@]}"

env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  "${CMAKE_BIN}" --build "${BUILD_DIR}" --target macKinect -j4

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - --timestamp=none "${APP_BUNDLE}"
else
  /usr/bin/codesign --force --deep --sign "${SIGN_IDENTITY}" --options runtime --timestamp "${APP_BUNDLE}"
fi
/usr/bin/codesign --verify --verbose=2 --deep "${APP_BUNDLE}"
rm -f "${APP_BUNDLE}/Contents/MacOS/macKinect.d"

rm -f "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUM_PATH}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DOCS_DIR}" "${STAGING_LICENSES_DIR}"

# Stage the distributable app separately so release-only cleanup can happen
# without mutating the locally built bundle that developers use for testing.
/usr/bin/ditto "${APP_BUNDLE}" "${STAGING_APP_BUNDLE}"
/bin/rm -f "${STAGING_APP_BUNDLE}/Contents/MacOS/macKinect.d"
/usr/bin/xattr -cr "${STAGING_APP_BUNDLE}" 2>/dev/null || true

if [[ "${INCLUDE_KINECT_V1_FIRMWARE}" != "1" ]]; then
  /bin/rm -f "${STAGING_APP_BUNDLE}/Contents/Resources/libfreenect/audios.bin"
fi

/bin/cp "${SCRIPT_DIR}/install-system-integration.sh" "${STAGING_DIR}/InstallSystemIntegration.command"
/bin/chmod +x "${STAGING_DIR}/InstallSystemIntegration.command"

for doc in README.md CHANGELOG.md DEPENDENCIES.md RELEASE_NOTES.md THIRD_PARTY_NOTICES.md LICENSE CONTRIBUTORS.md; do
  if [[ -f "${SCRIPT_DIR}/${doc}" ]]; then
    /bin/cp "${SCRIPT_DIR}/${doc}" "${STAGING_DOCS_DIR}/${doc}"
  fi
done

for license_path in \
  "${SCRIPT_DIR}/libfreenect/APACHE20" \
  "${SCRIPT_DIR}/libfreenect/GPL2" \
  "${SCRIPT_DIR}/libfreenect2/APACHE20" \
  "${SCRIPT_DIR}/libfreenect2/GPL2" \
  "${SCRIPT_DIR}/licenses/libusb/COPYING" \
  "${SCRIPT_DIR}/licenses/libjpeg-turbo/LICENSE.md"; do
  if [[ -f "${license_path}" ]]; then
    /bin/cp "${license_path}" "${STAGING_LICENSES_DIR}/$(basename "${license_path}")"
  fi
done

/usr/bin/xattr -cr "${STAGING_DIR}" 2>/dev/null || true
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc "${STAGING_DIR}" "${ZIP_PATH}"

DMG_CREATED=0
if /usr/bin/hdiutil create -volname "macKinect ${APP_VERSION}" -srcfolder "${STAGING_DIR}" -format UDZO "${DMG_PATH}"; then
  DMG_CREATED=1
else
  echo "Warning: DMG creation failed in this environment. ZIP artifact is available."
fi

rm -rf "${STAGING_DIR}"

/usr/bin/shasum -a 256 "${ZIP_PATH}" > "${CHECKSUM_PATH}"
if [[ "${DMG_CREATED}" -eq 1 ]]; then
  /usr/bin/shasum -a 256 "${DMG_PATH}" >> "${CHECKSUM_PATH}"
fi

echo "Packaged app:"
echo "  ${ZIP_PATH}"
if [[ "${DMG_CREATED}" -eq 1 ]]; then
  echo "  ${DMG_PATH}"
fi
echo "  ${CHECKSUM_PATH}"
echo "Version: ${APP_VERSION}"
echo "Signing identity: ${SIGN_IDENTITY}"
