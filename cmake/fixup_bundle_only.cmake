include(BundleUtilities)

if(NOT DEFINED APP_BUNDLE)
  message(FATAL_ERROR "APP_BUNDLE is required")
endif()

if(NOT EXISTS "${APP_BUNDLE}")
  message(FATAL_ERROR "Bundle path does not exist: ${APP_BUNDLE}")
endif()

set(search_dirs "")
if(DEFINED SEARCH_DIRS_PIPE AND NOT SEARCH_DIRS_PIPE STREQUAL "")
  string(REPLACE "|" ";" search_dirs "${SEARCH_DIRS_PIPE}")
endif()

fixup_bundle("${APP_BUNDLE}" "" "${search_dirs}")
