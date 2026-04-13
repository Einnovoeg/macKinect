#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build-installer}"
APP_BUNDLE="${BUILD_DIR}/macKinect.app"
DIST_DIR="${SCRIPT_DIR}/dist"
SANDBOX_HOME_DIR="${BUILD_DIR}/packaging-home"
STAMP="$(date +%Y%m%d-%H%M%S)"
PKG_ROOT="${DIST_DIR}/pkgroot-${STAMP}"
PKG_SCRIPTS="${DIST_DIR}/pkgscripts-${STAMP}"
APP_VERSION="1.0.0"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")"
fi
PKG_PATH="${DIST_DIR}/macKinect-Installer-${APP_VERSION}-${STAMP}.pkg"
MODULE_CACHE_DIR="${BUILD_DIR}/clang-module-cache"
APP_SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
PKG_SIGN_IDENTITY="${MACOS_PKG_SIGN_IDENTITY:-}"
INCLUDE_KINECT_V1_FIRMWARE="${INCLUDE_KINECT_V1_FIRMWARE:-0}"

if [[ -f "${SCRIPT_DIR}/VERSION" && -f "${BUILD_DIR}/macKinect.app/Contents/Info.plist" && "${SCRIPT_DIR}/VERSION" -nt "${BUILD_DIR}/macKinect.app/Contents/Info.plist" ]]; then
  echo "Clearing installer build directory because version metadata changed: ${BUILD_DIR}"
  find "${BUILD_DIR}" -mindepth 1 -depth -delete
fi

mkdir -p "${MODULE_CACHE_DIR}"
mkdir -p "${SANDBOX_HOME_DIR}"
env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" -G Ninja -DCMAKE_BUILD_TYPE=Release
env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  cmake --build "${BUILD_DIR}" --target macKinect -j4

if [[ "${APP_SIGN_IDENTITY}" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - --timestamp=none "${APP_BUNDLE}"
else
  /usr/bin/codesign --force --deep --sign "${APP_SIGN_IDENTITY}" --options runtime --timestamp "${APP_BUNDLE}"
fi
/usr/bin/codesign --verify --verbose=2 --deep "${APP_BUNDLE}"
/bin/rm -f "${APP_BUNDLE}/Contents/MacOS/macKinect.d"

/bin/mkdir -p "${DIST_DIR}"
/bin/rm -f "${PKG_PATH}"
/bin/rm -rf "${PKG_ROOT}" "${PKG_SCRIPTS}"

/bin/mkdir -p "${PKG_ROOT}/Applications"
/bin/mkdir -p "${PKG_ROOT}/Library/Audio/Plug-Ins/HAL"
/bin/mkdir -p "${PKG_ROOT}/Library/CoreMediaIO/Plug-Ins/DAL"
/usr/bin/ditto "${APP_BUNDLE}" "${PKG_ROOT}/Applications/macKinect.app"

if [[ "${INCLUDE_KINECT_V1_FIRMWARE}" != "1" ]]; then
  /bin/rm -f "${PKG_ROOT}/Applications/macKinect.app/Contents/Resources/libfreenect/audios.bin"
fi

HAL_SRC="${PKG_ROOT}/Applications/macKinect.app/Contents/PlugIns/HAL/KinectAudioHAL.driver"
HAL_DST="${PKG_ROOT}/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver"
DAL_SRC="${PKG_ROOT}/Applications/macKinect.app/Contents/PlugIns/DAL/KinectCameraDAL.plugin"
DAL_DST="${PKG_ROOT}/Library/CoreMediaIO/Plug-Ins/DAL/KinectCameraDAL.plugin"
APP_FRAMEWORKS_DIR="${PKG_ROOT}/Applications/macKinect.app/Contents/Frameworks"
CODESIGN_IDENTITY="${APP_SIGN_IDENTITY}"

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  APP_AUTHORITY="$(/usr/bin/codesign -dv --verbose=2 "${APP_BUNDLE}" 2>&1 | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
  if [[ -n "${APP_AUTHORITY}" ]]; then
    CODESIGN_IDENTITY="${APP_AUTHORITY}"
  fi
fi

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "Refusing to package an installer with ad hoc-signed HAL/DAL bundles." >&2
  echo "Build the app with a real Apple Developer signing identity before creating a system-integration installer." >&2
  exit 3
fi

/usr/bin/ditto "${HAL_SRC}" "${HAL_DST}"
/usr/bin/ditto "${DAL_SRC}" "${DAL_DST}"

DAL_FRAMEWORKS_DIR="${DAL_DST}/Contents/Frameworks"
/bin/mkdir -p "${DAL_FRAMEWORKS_DIR}"
for pattern in "libfreenect.0*.dylib" "libfreenect2*.dylib" "libusb-1.0*.dylib" "libturbojpeg*.dylib"; do
  for lib in "${APP_FRAMEWORKS_DIR}"/${pattern}; do
    [[ -e "${lib}" ]] || continue
    /usr/bin/ditto "${lib}" "${DAL_FRAMEWORKS_DIR}/$(basename "${lib}")"
  done
done

DAL_BIN="${DAL_DST}/Contents/MacOS/KinectCameraDAL"
if [[ ! -f "${DAL_BIN}" && -f "${DAL_DST}/KinectCameraDAL" ]]; then
  DAL_BIN="${DAL_DST}/KinectCameraDAL"
  DAL_FRAMEWORKS_DIR="${DAL_DST}/Frameworks"
  /bin/mkdir -p "${DAL_FRAMEWORKS_DIR}"
fi

if [[ -f "${DAL_BIN}" ]]; then
  /usr/bin/install_name_tool -add_rpath "@loader_path/../Frameworks" "${DAL_BIN}" >/dev/null 2>&1 || true
  /usr/bin/install_name_tool -change "/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "${DAL_BIN}" || true
  /usr/bin/install_name_tool -change "/opt/homebrew/opt/jpeg-turbo/lib/libturbojpeg.0.dylib" "@rpath/libturbojpeg.0.dylib" "${DAL_BIN}" || true
fi

if [[ -f "${DAL_FRAMEWORKS_DIR}/libfreenect.0.7.5.dylib" ]]; then
  /usr/bin/install_name_tool -id "@rpath/libfreenect.0.7.5.dylib" "${DAL_FRAMEWORKS_DIR}/libfreenect.0.7.5.dylib" || true
  /usr/bin/install_name_tool -change "@executable_path/../Frameworks/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "${DAL_FRAMEWORKS_DIR}/libfreenect.0.7.5.dylib" || true
fi
if [[ -f "${DAL_FRAMEWORKS_DIR}/libfreenect2.0.2.0.dylib" ]]; then
  /usr/bin/install_name_tool -id "@rpath/libfreenect2.0.2.0.dylib" "${DAL_FRAMEWORKS_DIR}/libfreenect2.0.2.0.dylib" || true
  /usr/bin/install_name_tool -change "@executable_path/../Frameworks/libusb-1.0.0.dylib" "@rpath/libusb-1.0.0.dylib" "${DAL_FRAMEWORKS_DIR}/libfreenect2.0.2.0.dylib" || true
  /usr/bin/install_name_tool -change "@executable_path/../Frameworks/libturbojpeg.0.dylib" "@rpath/libturbojpeg.0.dylib" "${DAL_FRAMEWORKS_DIR}/libfreenect2.0.2.0.dylib" || true
fi
if [[ -f "${DAL_FRAMEWORKS_DIR}/libusb-1.0.0.dylib" ]]; then
  /usr/bin/install_name_tool -id "@rpath/libusb-1.0.0.dylib" "${DAL_FRAMEWORKS_DIR}/libusb-1.0.0.dylib" || true
fi
if [[ -f "${DAL_FRAMEWORKS_DIR}/libturbojpeg.0.4.0.dylib" ]]; then
  /usr/bin/install_name_tool -id "@rpath/libturbojpeg.0.4.0.dylib" "${DAL_FRAMEWORKS_DIR}/libturbojpeg.0.4.0.dylib" || true
fi

/usr/bin/codesign --force --deep --sign "${CODESIGN_IDENTITY}" --timestamp=none "${HAL_DST}"
/usr/bin/codesign --force --deep --sign "${CODESIGN_IDENTITY}" --timestamp=none "${DAL_DST}"
/usr/bin/codesign --verify --verbose=2 --deep "${HAL_DST}"
/usr/bin/codesign --verify --verbose=2 --deep "${DAL_DST}"

/bin/mkdir -p "${PKG_SCRIPTS}"
cat > "${PKG_SCRIPTS}/postinstall" <<'EOF'
#!/bin/bash
/usr/bin/killall coreaudiod >/dev/null 2>&1 || true
/usr/bin/killall VDCAssistant AppleCameraAssistant >/dev/null 2>&1 || true
exit 0
EOF
/bin/chmod +x "${PKG_SCRIPTS}/postinstall"

if [[ -n "${PKG_SIGN_IDENTITY}" ]]; then
  /usr/bin/pkgbuild \
    --root "${PKG_ROOT}" \
    --scripts "${PKG_SCRIPTS}" \
    --identifier "com.mackinect.installer" \
    --version "${APP_VERSION}" \
    --install-location "/" \
    --sign "${PKG_SIGN_IDENTITY}" \
    "${PKG_PATH}"
else
  /usr/bin/pkgbuild \
    --root "${PKG_ROOT}" \
    --scripts "${PKG_SCRIPTS}" \
    --identifier "com.mackinect.installer" \
    --version "${APP_VERSION}" \
    --install-location "/" \
    "${PKG_PATH}"
fi

/bin/rm -rf "${PKG_ROOT}" "${PKG_SCRIPTS}"

echo "Installer package:"
echo "  ${PKG_PATH}"
echo "Version: ${APP_VERSION}"
