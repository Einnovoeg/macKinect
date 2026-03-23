include(BundleUtilities)

if(NOT DEFINED APP_BUNDLE)
  message(FATAL_ERROR "APP_BUNDLE is required")
endif()

if(NOT EXISTS "${APP_BUNDLE}")
  message(FATAL_ERROR "Bundle path does not exist: ${APP_BUNDLE}")
endif()

# Some generators can leave a stale executable at the bundle root. Remove it so
# fixup/verification only process the real app binary in Contents/MacOS.
if(EXISTS "${APP_BUNDLE}/macKinect")
  file(REMOVE "${APP_BUNDLE}/macKinect")
endif()
if(EXISTS "${APP_BUNDLE}/macKinect.d")
  file(REMOVE "${APP_BUNDLE}/macKinect.d")
endif()
if(EXISTS "${APP_BUNDLE}/Info.plist")
  file(REMOVE "${APP_BUNDLE}/Info.plist")
endif()
if(EXISTS "${APP_BUNDLE}/Contents/MacOS/macKinect.d")
  file(REMOVE "${APP_BUNDLE}/Contents/MacOS/macKinect.d")
endif()

set(search_dirs "")
if(DEFINED SEARCH_DIRS_PIPE AND NOT SEARCH_DIRS_PIPE STREQUAL "")
  string(REPLACE "|" ";" search_dirs "${SEARCH_DIRS_PIPE}")
endif()

# Ensure dependencies are copied into the app bundle (Frameworks) and relinked.
fixup_bundle("${APP_BUNDLE}" "" "${search_dirs}")

if(APPLE)
  find_program(CODESIGN_EXECUTABLE codesign)
  if(NOT CODESIGN_EXECUTABLE)
    message(WARNING "codesign not found; bundle may fail to launch on systems enforcing strict validation.")
  else()
    set(codesign_identity "-")
    if(DEFINED CODESIGN_IDENTITY AND NOT CODESIGN_IDENTITY STREQUAL "")
      set(codesign_identity "${CODESIGN_IDENTITY}")
    endif()

    set(app_entitlements_path "")
    if(DEFINED APP_ENTITLEMENTS_PLIST AND EXISTS "${APP_ENTITLEMENTS_PLIST}")
      set(app_entitlements_path "${APP_ENTITLEMENTS_PLIST}")
    endif()

    set(system_extension_entitlements_path "")
    if(DEFINED SYSTEM_EXTENSION_ENTITLEMENTS_PLIST AND EXISTS "${SYSTEM_EXTENSION_ENTITLEMENTS_PLIST}")
      set(system_extension_entitlements_path "${SYSTEM_EXTENSION_ENTITLEMENTS_PLIST}")
    endif()

    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E env
      "CODESIGN_EXECUTABLE=${CODESIGN_EXECUTABLE}"
      "CODESIGN_IDENTITY=${codesign_identity}"
      "APP_BUNDLE=${APP_BUNDLE}"
      "APP_ENTITLEMENTS_PLIST=${app_entitlements_path}"
      "SYSTEM_EXTENSION_ENTITLEMENTS_PLIST=${system_extension_entitlements_path}"
      /bin/bash -lc
      "set -euo pipefail
app_entitlements_args=()
if [[ -n \"$APP_ENTITLEMENTS_PLIST\" && -f \"$APP_ENTITLEMENTS_PLIST\" ]]; then
  app_entitlements_args=(--entitlements \"$APP_ENTITLEMENTS_PLIST\")
fi

system_extension_entitlements_args=()
if [[ -n \"$SYSTEM_EXTENSION_ENTITLEMENTS_PLIST\" && -f \"$SYSTEM_EXTENSION_ENTITLEMENTS_PLIST\" ]]; then
  system_extension_entitlements_args=(--entitlements \"$SYSTEM_EXTENSION_ENTITLEMENTS_PLIST\")
fi

# Finder metadata inside nested bundles breaks codesign with \"unsealed
# contents present in the bundle root\", so scrub it before re-signing.
find \"$APP_BUNDLE/Contents\" -name '.DS_Store' -delete
/usr/bin/xattr -cr \"$APP_BUNDLE\" 2>/dev/null || true
find \"$APP_BUNDLE/Contents\" -depth \\( -name '*.driver' -o -name '*.plugin' \\) -print0 | while IFS= read -r -d '' nested_bundle; do
  find \"$nested_bundle\" -mindepth 1 -maxdepth 1 ! -name 'Contents' ! -name '_CodeSignature' -exec /bin/rm -rf {} +
done

find \"$APP_BUNDLE/Contents\" -depth \\( -name '*.framework' -o -name '*.dylib' -o -name '*.so' -o -name '*.plugin' -o -name '*.driver' -o -name '*.systemextension' -o -path '*/Contents/MacOS/*' \\) -print0 | while IFS= read -r -d '' item; do
  case \"$item\" in
    \"$APP_BUNDLE/Contents/MacOS/macKinect\") continue ;;
    *.systemextension)
      \"$CODESIGN_EXECUTABLE\" --force --sign \"$CODESIGN_IDENTITY\" --timestamp=none \"\${system_extension_entitlements_args[@]}\" \"$item\"
      ;;
    *)
      \"$CODESIGN_EXECUTABLE\" --force --sign \"$CODESIGN_IDENTITY\" --timestamp=none \"$item\"
      ;;
  esac
done
\"$CODESIGN_EXECUTABLE\" --force --sign \"$CODESIGN_IDENTITY\" --timestamp=none \"\${app_entitlements_args[@]}\" \"$APP_BUNDLE\""
      RESULT_VARIABLE nested_sign_rc
      OUTPUT_VARIABLE nested_sign_out
      ERROR_VARIABLE nested_sign_err
    )
    if(NOT nested_sign_rc EQUAL 0)
      message(FATAL_ERROR "codesign failed for ${APP_BUNDLE}\n${nested_sign_out}\n${nested_sign_err}")
    endif()

    execute_process(
      COMMAND "${CODESIGN_EXECUTABLE}" --verify --verbose=2 --deep "${APP_BUNDLE}"
      RESULT_VARIABLE verify_rc
      OUTPUT_VARIABLE verify_out
      ERROR_VARIABLE verify_err
    )
    if(NOT verify_rc EQUAL 0)
      message(FATAL_ERROR "codesign verification failed for ${APP_BUNDLE}\n${verify_out}\n${verify_err}")
    endif()
  endif()
endif()
