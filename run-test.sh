#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build-smoke}"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
SANDBOX_HOME_DIR="${BUILD_DIR}/test-home"

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
APP_BINARY="${BUILD_DIR}/macKinect.app/Contents/MacOS/macKinect"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${SANDBOX_HOME_DIR}"

if [[ -f "${SCRIPT_DIR}/VERSION" && -f "${BUILD_DIR}/macKinect.app/Contents/Info.plist" && "${SCRIPT_DIR}/VERSION" -nt "${BUILD_DIR}/macKinect.app/Contents/Info.plist" ]]; then
  echo "==> Clearing stale smoke-test build directory because version metadata changed"
  find "${BUILD_DIR}" -mindepth 1 -depth -delete
  mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${SANDBOX_HOME_DIR}"
fi

CONFIGURE_ARGS=(
  -S "${SCRIPT_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_BUILD_TYPE=Release
)
if [[ -n "${NINJA_BIN}" ]]; then
  CONFIGURE_ARGS+=(-G Ninja "-DCMAKE_MAKE_PROGRAM=${NINJA_BIN}")
fi

echo "==> Configuring"
env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  "${CMAKE_BIN}" "${CONFIGURE_ARGS[@]}"

echo "==> Building"
env \
  HOME="${SANDBOX_HOME_DIR}" \
  SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  "${CMAKE_BIN}" --build "${BUILD_DIR}" --target macKinect -j4

echo "==> Smoke tests"
"${APP_BINARY}" --help
"${APP_BINARY}" --version
"${APP_BINARY}" --list
"${APP_BINARY}" --integration-status

echo "Smoke tests passed."
