cmake_minimum_required(VERSION 3.15)

set(KINECT_PROJECT_VERSION "1.0.0")
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" KINECT_VERSION_FILE LIMIT_COUNT 1)
    if(KINECT_VERSION_FILE)
        string(STRIP "${KINECT_VERSION_FILE}" KINECT_PROJECT_VERSION)
    endif()
endif()

project(macKinect VERSION ${KINECT_PROJECT_VERSION} LANGUAGES CXX C OBJCXX Swift)

if(POLICY CMP0144)
    cmake_policy(SET CMP0144 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(KINECT_BUILD_BUNDLED_LIBFREENECT2 "Build workspace libfreenect2 source if no package is found" ON)
option(KINECT_BUILD_AUDIO_HAL_PLUGIN "Build CoreAudio HAL virtual microphone plugin target" ON)
option(KINECT_BUILD_CAMERA_DAL_PLUGIN "Build CoreMediaIO DAL virtual camera plugin target" ON)
option(KINECT_BUILD_CAMERA_SYSTEM_EXTENSION "Build CoreMediaIO Camera Extension system extension target" ON)
option(KINECT_ENABLE_SYSTEM_EXTENSION_INSTALL_ENTITLEMENT "Embed the app entitlement required to activate a system extension when a provisioning profile is available" ON)
set(KINECT_CODESIGN_IDENTITY "" CACHE STRING "macOS codesigning identity for app and plugins. Empty uses ad-hoc signing.")
set(KINECT_DEVELOPMENT_TEAM_ID "" CACHE STRING "Apple development team identifier used for the camera extension Mach service name")
set(KINECT_APP_PROVISIONING_PROFILE "" CACHE FILEPATH "Path to a provisioning profile for macKinect system-extension activation")
set(KINECT_BUNDLE_VERSION "${PROJECT_VERSION}")

set(KINECT_EFFECTIVE_CODESIGN_IDENTITY "${KINECT_CODESIGN_IDENTITY}")
set(KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID "${KINECT_DEVELOPMENT_TEAM_ID}")

if(APPLE AND (KINECT_EFFECTIVE_CODESIGN_IDENTITY STREQUAL "" OR KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID STREQUAL ""))
    find_program(SECURITY_EXECUTABLE security)
    if(SECURITY_EXECUTABLE)
        execute_process(
            COMMAND "${SECURITY_EXECUTABLE}" find-identity -v -p codesigning
            RESULT_VARIABLE _mackinect_identity_rc
            OUTPUT_VARIABLE _mackinect_identity_output
            ERROR_VARIABLE _mackinect_identity_error
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_STRIP_TRAILING_WHITESPACE
        )
        if(_mackinect_identity_rc EQUAL 0)
            string(REGEX MATCHALL "\"Apple Development:[^\"]+\\([A-Z0-9]+\\)\"" _mackinect_apple_development_matches "${_mackinect_identity_output}")
            list(LENGTH _mackinect_apple_development_matches _mackinect_apple_development_match_count)
            if(_mackinect_apple_development_match_count EQUAL 1)
                list(GET _mackinect_apple_development_matches 0 _mackinect_detected_identity)
                string(REGEX REPLACE "^\"|\"$" "" _mackinect_detected_identity "${_mackinect_detected_identity}")
                set(_mackinect_detected_team_id "")
                find_program(OPENSSL_EXECUTABLE openssl)
                if(OPENSSL_EXECUTABLE)
                    execute_process(
                        COMMAND /bin/bash -lc "set -euo pipefail; \"$1\" find-certificate -c \"$2\" -p | \"$3\" x509 -noout -subject -nameopt RFC2253"
                        _
                        "${SECURITY_EXECUTABLE}"
                        "${_mackinect_detected_identity}"
                        "${OPENSSL_EXECUTABLE}"
                        RESULT_VARIABLE _mackinect_subject_rc
                        OUTPUT_VARIABLE _mackinect_subject_output
                        ERROR_QUIET
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                    )
                    if(_mackinect_subject_rc EQUAL 0 AND _mackinect_subject_output MATCHES "OU=([A-Z0-9]+)")
                        string(REGEX REPLACE ".*OU=([A-Z0-9]+).*" "\\1" _mackinect_detected_team_id "${_mackinect_subject_output}")
                    endif()
                endif()
                if(_mackinect_detected_team_id STREQUAL "")
                    string(REGEX REPLACE ".*\\(([A-Z0-9]+)\\).*" "\\1" _mackinect_detected_team_id "${_mackinect_detected_identity}")
                endif()
                if(KINECT_EFFECTIVE_CODESIGN_IDENTITY STREQUAL "")
                    set(KINECT_EFFECTIVE_CODESIGN_IDENTITY "${_mackinect_detected_identity}")
                endif()
                if(KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID STREQUAL "")
                    set(KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID "${_mackinect_detected_team_id}")
                endif()
            endif()
        endif()
    endif()
endif()

if(APPLE)
    if(KINECT_EFFECTIVE_CODESIGN_IDENTITY STREQUAL "")
        message(STATUS "Using ad-hoc codesigning for macKinect bundles")
    else()
        message(STATUS "Using codesigning identity: ${KINECT_EFFECTIVE_CODESIGN_IDENTITY}")
    endif()

    if(KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID STREQUAL "")
        message(WARNING "No development team id configured or auto-detected. Camera extension activation may fail until KINECT_DEVELOPMENT_TEAM_ID is set.")
    else()
        message(STATUS "Using development team id: ${KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID}")
    endif()
endif()

set(KINECT_APP_SYSTEM_EXTENSION_INSTALL_ENTITLEMENT_BLOCK "")
set(KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST "${CMAKE_BINARY_DIR}/app_entitlements.plist")
set(KINECT_HAS_APP_PROVISIONING_PROFILE OFF)
if(EXISTS "${KINECT_APP_PROVISIONING_PROFILE}")
    set(KINECT_HAS_APP_PROVISIONING_PROFILE ON)
endif()

if(KINECT_ENABLE_SYSTEM_EXTENSION_INSTALL_ENTITLEMENT)
    if(KINECT_HAS_APP_PROVISIONING_PROFILE)
        set(KINECT_APP_SYSTEM_EXTENSION_INSTALL_ENTITLEMENT_BLOCK "    <key>com.apple.developer.system-extension.install</key>\n    <true/>\n")
        message(STATUS "Using provisioning profile for system-extension activation: ${KINECT_APP_PROVISIONING_PROFILE}")
    elseif(APPLE)
        message(WARNING "No provisioning profile configured for macKinect. Building without the system-extension install entitlement so the app remains launchable. Set KINECT_APP_PROVISIONING_PROFILE to enable activation.")
    endif()
endif()

configure_file(
    "${CMAKE_SOURCE_DIR}/app_entitlements.plist"
    "${KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST}"
    @ONLY
)

# Prefer ARM64 default on Apple Silicon, but allow explicit override (for Intel/universal builds).
if(APPLE AND (NOT DEFINED CMAKE_OSX_ARCHITECTURES OR CMAKE_OSX_ARCHITECTURES STREQUAL ""))
    set(_mackinect_default_arch "")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$")
        set(_mackinect_default_arch "arm64")
    else()
        execute_process(
            COMMAND /usr/bin/arch -arm64 /usr/bin/uname -m
            RESULT_VARIABLE _arm64_probe_rc
            OUTPUT_VARIABLE _arm64_probe_arch
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        # Handles CMake/toolchain processor reporting x86_64 when running under Rosetta.
        if(_arm64_probe_rc EQUAL 0 AND _arm64_probe_arch MATCHES "^(arm64|aarch64)$")
            set(_mackinect_default_arch "arm64")
        endif()
    endif()
    if(_mackinect_default_arch)
        set(CMAKE_OSX_ARCHITECTURES "${_mackinect_default_arch}" CACHE STRING "macOS target architectures" FORCE)
    endif()
endif()

set(KINECT_V1_FIRMWARE_PATH "")
set(KINECT_V1_FIRMWARE_CANDIDATES
    "${CMAKE_SOURCE_DIR}/firmware/audios.bin"
    "${CMAKE_SOURCE_DIR}/../libfreenect/src/audios.bin"
    "${CMAKE_SOURCE_DIR}/../libfreenect/build/src/audios.bin"
)
foreach(_fw_candidate IN LISTS KINECT_V1_FIRMWARE_CANDIDATES)
    if(EXISTS "${_fw_candidate}")
        set(KINECT_V1_FIRMWARE_PATH "${_fw_candidate}")
        break()
    endif()
endforeach()
if(KINECT_V1_FIRMWARE_PATH)
    message(STATUS "Kinect v1 firmware found: ${KINECT_V1_FIRMWARE_PATH}")
else()
    message(WARNING "Kinect v1 audios.bin firmware not found. v1 camera/mic startup may fail until firmware is provided.")
endif()

# --- CoreAudio HAL virtual microphone plugin ---
if(APPLE AND KINECT_BUILD_AUDIO_HAL_PLUGIN)
    set(KINECT_HAL_EXECUTABLE_NAME "KinectAudioHAL")
    set(KINECT_HAL_BUNDLE_ID "com.mackinect.audiohal")
    set(KINECT_HAL_BUNDLE_VERSION "${KINECT_BUNDLE_VERSION}")
    configure_file(
        "${CMAKE_SOURCE_DIR}/src/hal_plugin/Info.plist.in"
        "${CMAKE_BINARY_DIR}/KinectAudioHAL-Info.plist"
        @ONLY
    )

    add_library(KinectAudioHAL MODULE
        src/hal_plugin/KinectAudioHALPlugin.cpp
    )
    target_link_libraries(KinectAudioHAL PRIVATE
        "-framework CoreAudio"
        "-framework CoreFoundation"
    )
    target_compile_definitions(KinectAudioHAL PRIVATE GL_SILENCE_DEPRECATION)
    set_target_properties(KinectAudioHAL PROPERTIES
        BUNDLE TRUE
        BUNDLE_EXTENSION "driver"
        PREFIX ""
        OUTPUT_NAME "${KINECT_HAL_EXECUTABLE_NAME}"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/KinectAudioHAL-Info.plist"
    )

    add_custom_target(install-kinect-audio-hal
        COMMAND ${CMAKE_COMMAND} -E echo "Install with:"
        COMMAND ${CMAKE_COMMAND} -E echo "  sudo ditto $<TARGET_BUNDLE_DIR:KinectAudioHAL> /Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver"
        DEPENDS KinectAudioHAL
        VERBATIM
    )
endif()

# Find OpenGL and GLUT
find_package(OpenGL REQUIRED)
find_package(GLUT REQUIRED)

# Find libfreenect (v1) - Try in-repo and sibling paths first
set(LIBFREENECT_ROOT "${CMAKE_SOURCE_DIR}/libfreenect" CACHE PATH "Path to libfreenect source/install")
set(LIBFREENECT_ALT_ROOT "${CMAKE_SOURCE_DIR}/../libfreenect")

find_path(FREENECT_INCLUDE_DIR libfreenect.h
    HINTS 
        ${LIBFREENECT_ROOT}/include
        ${LIBFREENECT_ROOT}/src
        ${LIBFREENECT_ALT_ROOT}/include
        ${LIBFREENECT_ALT_ROOT}/src
        /usr/local/include 
        /opt/homebrew/include
)

find_library(FREENECT_LIBRARY freenect
    HINTS 
        ${LIBFREENECT_ROOT}/build/lib
        ${LIBFREENECT_ROOT}/lib
        ${LIBFREENECT_ALT_ROOT}/build/lib
        ${LIBFREENECT_ALT_ROOT}/lib
        /usr/local/lib 
        /opt/homebrew/lib
)

if(FREENECT_LIBRARY)
    get_filename_component(FREENECT_LIBRARY_DIR "${FREENECT_LIBRARY}" DIRECTORY)
endif()

set(KINECT_HAVE_LIBFREENECT OFF)
set(KINECT_HAVE_LIBFREENECT2 OFF)

if(FREENECT_INCLUDE_DIR AND FREENECT_LIBRARY)
    set(KINECT_HAVE_LIBFREENECT ON)
endif()

if(TARGET KinectAudioHAL)
    if(FREENECT_INCLUDE_DIR)
        target_include_directories(KinectAudioHAL PRIVATE ${FREENECT_INCLUDE_DIR})
    endif()
    if(KINECT_HAVE_LIBFREENECT)
        target_link_libraries(KinectAudioHAL PRIVATE ${FREENECT_LIBRARY})
    endif()
    target_compile_definitions(KinectAudioHAL PRIVATE
        KINECT_HAVE_LIBFREENECT=$<BOOL:${KINECT_HAVE_LIBFREENECT}>
    )
endif()

# Find/build libfreenect2 (v2) - optional
set(LIBFREENECT2_TARGET "")
set(LIBFREENECT2_INCLUDE_DIRS "")
find_package(libfreenect2 QUIET CONFIG)
if(libfreenect2_FOUND)
    set(KINECT_HAVE_LIBFREENECT2 ON)
    set(LIBFREENECT2_TARGET libfreenect2::freenect2)
endif()

set(KINECT_LIBFREENECT2_ROOT "${CMAKE_SOURCE_DIR}/libfreenect2" CACHE PATH "Path to libfreenect2 source tree")
set(KINECT_LIBFREENECT2_ALT_ROOT "${CMAKE_SOURCE_DIR}/../libfreenect2")
if(NOT KINECT_HAVE_LIBFREENECT2 AND KINECT_BUILD_BUNDLED_LIBFREENECT2)
    if(EXISTS "${KINECT_LIBFREENECT2_ROOT}/CMakeLists.txt")
        set(KINECT_LIBFREENECT2_SOURCE_DIR "${KINECT_LIBFREENECT2_ROOT}")
    elseif(EXISTS "${KINECT_LIBFREENECT2_ALT_ROOT}/CMakeLists.txt")
        set(KINECT_LIBFREENECT2_SOURCE_DIR "${KINECT_LIBFREENECT2_ALT_ROOT}")
    endif()
endif()

if(NOT KINECT_HAVE_LIBFREENECT2 AND KINECT_BUILD_BUNDLED_LIBFREENECT2 AND DEFINED KINECT_LIBFREENECT2_SOURCE_DIR)
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)
    set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(BUILD_OPENNI2_DRIVER OFF CACHE BOOL "" FORCE)
    set(BUILD_STREAMER_RECORDER OFF CACHE BOOL "" FORCE)
    set(ENABLE_CXX11 ON CACHE BOOL "" FORCE)
    set(ENABLE_OPENCL OFF CACHE BOOL "" FORCE)
    set(ENABLE_CUDA OFF CACHE BOOL "" FORCE)
    set(ENABLE_OPENGL OFF CACHE BOOL "" FORCE)
    set(ENABLE_VAAPI OFF CACHE BOOL "" FORCE)
    set(ENABLE_TEGRAJPEG OFF CACHE BOOL "" FORCE)
    add_subdirectory("${KINECT_LIBFREENECT2_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/third_party/libfreenect2")
    set(KINECT_HAVE_LIBFREENECT2 ON)
    set(LIBFREENECT2_TARGET freenect2)
    set(LIBFREENECT2_INCLUDE_DIRS
        "${KINECT_LIBFREENECT2_SOURCE_DIR}/include"
        "${CMAKE_BINARY_DIR}/third_party/libfreenect2"
    )
endif()

# Sources
set(SOURCES
    src/main.cpp
    src/gui/app.cpp
    src/backends/freenect_v1_backend.cpp
    src/backends/freenect_v2_backend.cpp
)

set(CONTROL_CENTER_SOURCES
    src/control_center_v1.cpp
)

# Check backend availability
if(KINECT_HAVE_LIBFREENECT)
    message(STATUS "Kinect v1 support enabled. Include: ${FREENECT_INCLUDE_DIR}, Lib: ${FREENECT_LIBRARY}")
else()
    message(WARNING "libfreenect not found - v1 support disabled")
endif()

if(KINECT_HAVE_LIBFREENECT2)
    message(STATUS "Kinect v2 support enabled")
else()
    message(STATUS "Kinect v2 support disabled (libfreenect2 not found)")
endif()

# Silence macOS deprecation warnings for OpenGL
add_definitions(-DGL_SILENCE_DEPRECATION)

# --- Legacy C++ App ---
add_executable(KinectMacOsApp ${SOURCES})

target_include_directories(KinectMacOsApp PRIVATE
    src
)
if(FREENECT_INCLUDE_DIR)
    target_include_directories(KinectMacOsApp PRIVATE ${FREENECT_INCLUDE_DIR})
endif()
if(LIBFREENECT2_INCLUDE_DIRS)
    target_include_directories(KinectMacOsApp PRIVATE ${LIBFREENECT2_INCLUDE_DIRS})
endif()

if(KINECT_HAVE_LIBFREENECT2)
    target_link_libraries(KinectMacOsApp PRIVATE ${LIBFREENECT2_TARGET})
endif()

if(KINECT_HAVE_LIBFREENECT)
    target_link_libraries(KinectMacOsApp PRIVATE ${FREENECT_LIBRARY})
endif()

target_link_libraries(KinectMacOsApp PRIVATE
    OpenGL::GL
    GLUT::GLUT
)
target_compile_definitions(KinectMacOsApp PRIVATE
    GL_SILENCE_DEPRECATION
    KINECT_HAVE_LIBFREENECT=$<BOOL:${KINECT_HAVE_LIBFREENECT}>
    KINECT_HAVE_LIBFREENECT2=$<BOOL:${KINECT_HAVE_LIBFREENECT2}>
)

# --- Kinect Control Center (native OpenGL v1 control app) ---
if(KINECT_HAVE_LIBFREENECT)
    get_filename_component(FREENECT_LIBRARY_DIR "${FREENECT_LIBRARY}" DIRECTORY)
    add_executable(kinect-control-center ${CONTROL_CENTER_SOURCES})
    target_include_directories(kinect-control-center PRIVATE ${FREENECT_INCLUDE_DIR})
    target_link_libraries(kinect-control-center PRIVATE
        ${FREENECT_LIBRARY}
        OpenGL::GL
        GLUT::GLUT
    )
    target_compile_definitions(kinect-control-center PRIVATE
        GL_SILENCE_DEPRECATION
        KINECT_HAVE_LIBFREENECT=1
        KINECT_HAVE_LIBFREENECT2=0
    )
    set_target_properties(kinect-control-center PROPERTIES
        BUILD_RPATH "${FREENECT_LIBRARY_DIR}"
        INSTALL_RPATH "${FREENECT_LIBRARY_DIR}"
    )
    message(STATUS "kinect-control-center target enabled")
else()
    message(WARNING "kinect-control-center target disabled because libfreenect was not found")
endif()

# --- CoreMediaIO DAL virtual camera plugin ---
if(APPLE AND KINECT_BUILD_CAMERA_DAL_PLUGIN)
    set(KINECT_DAL_EXECUTABLE_NAME "KinectCameraDAL")
    set(KINECT_DAL_BUNDLE_ID "com.mackinect.cameradal")
    set(KINECT_DAL_BUNDLE_VERSION "${KINECT_BUNDLE_VERSION}")
    configure_file(
        "${CMAKE_SOURCE_DIR}/src/dal_plugin/Info.plist.in"
        "${CMAKE_BINARY_DIR}/KinectCameraDAL-Info.plist"
        @ONLY
    )

    add_library(KinectCameraDAL MODULE
        src/dal_plugin/KinectCameraDALPlugin.cpp
        src/backends/freenect_v1_backend.cpp
        src/backends/freenect_v2_backend.cpp
    )
    target_include_directories(KinectCameraDAL PRIVATE
        src
    )
    if(FREENECT_INCLUDE_DIR)
        target_include_directories(KinectCameraDAL PRIVATE ${FREENECT_INCLUDE_DIR})
    endif()
    if(LIBFREENECT2_INCLUDE_DIRS)
        target_include_directories(KinectCameraDAL PRIVATE ${LIBFREENECT2_INCLUDE_DIRS})
    endif()
    if(KINECT_HAVE_LIBFREENECT)
        target_link_libraries(KinectCameraDAL PRIVATE ${FREENECT_LIBRARY})
    endif()
    if(KINECT_HAVE_LIBFREENECT2)
        target_link_libraries(KinectCameraDAL PRIVATE ${LIBFREENECT2_TARGET})
    endif()
    target_link_libraries(KinectCameraDAL PRIVATE
        "-framework CoreMediaIO"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework CoreFoundation"
        "-framework CoreAudio"
    )
    target_compile_definitions(KinectCameraDAL PRIVATE
        GL_SILENCE_DEPRECATION
        KINECT_HAVE_LIBFREENECT=$<BOOL:${KINECT_HAVE_LIBFREENECT}>
        KINECT_HAVE_LIBFREENECT2=$<BOOL:${KINECT_HAVE_LIBFREENECT2}>
    )
    set_target_properties(KinectCameraDAL PROPERTIES
        BUNDLE TRUE
        BUNDLE_EXTENSION "plugin"
        PREFIX ""
        OUTPUT_NAME "${KINECT_DAL_EXECUTABLE_NAME}"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/KinectCameraDAL-Info.plist"
        BUILD_RPATH "@loader_path/Frameworks;@loader_path/../../../Frameworks"
        INSTALL_RPATH "@loader_path/Frameworks;@loader_path/../../../Frameworks"
    )

    add_custom_target(install-kinect-camera-dal
        COMMAND ${CMAKE_COMMAND} -E echo "Install with:"
        COMMAND ${CMAKE_COMMAND} -E echo "  ${CMAKE_SOURCE_DIR}/install-system-integration.sh ${CMAKE_BINARY_DIR}/macKinect.app"
        DEPENDS KinectCameraDAL
        VERBATIM
    )
endif()

# --- Swift / Objective-C Bridge (Modern App) ---

enable_language(Swift)

if(CMAKE_Swift_COMPILER)
    message(STATUS "Swift compiler found: ${CMAKE_Swift_COMPILER}")
    
    set(SWIFT_SOURCES
        src/swift/KinectEntrypoint.swift
        src/swift/KinectApp.swift
        src/swift/ContentView.swift
        src/swift/DiagnosticsLogger.swift
        src/swift/KinectManager.swift
        src/swift/ParsingHelpers.swift
        src/swift/PreviewMovieRecorder.swift
    )
    
    set(BRIDGE_SOURCES
        src/bridge/KinectBridge.mm
        src/backends/freenect_v1_backend.cpp
        src/backends/freenect_v2_backend.cpp
    )
    set_source_files_properties(src/bridge/KinectBridge.mm PROPERTIES
        COMPILE_OPTIONS "-fobjc-arc"
    )
    set_source_files_properties(src/bridge/OBSSyphonPublisher.mm PROPERTIES
        COMPILE_OPTIONS "-fobjc-arc"
    )
    set(SWIFT_BRIDGE_COMPILE_OPTIONS
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_SOURCE_DIR}/src/bridge/KinectBridge.h>"
    )
    set(SWIFT_COMMON_COMPILE_DEFINITIONS
        GL_SILENCE_DEPRECATION
        "$<$<NOT:$<COMPILE_LANGUAGE:Swift>>:KINECT_HAVE_LIBFREENECT=$<BOOL:${KINECT_HAVE_LIBFREENECT}>>"
        "$<$<NOT:$<COMPILE_LANGUAGE:Swift>>:KINECT_HAVE_LIBFREENECT2=$<BOOL:${KINECT_HAVE_LIBFREENECT2}>>"
        "$<$<AND:$<COMPILE_LANGUAGE:Swift>,$<BOOL:${KINECT_HAVE_LIBFREENECT}>>:KINECT_HAVE_LIBFREENECT>"
        "$<$<AND:$<COMPILE_LANGUAGE:Swift>,$<BOOL:${KINECT_HAVE_LIBFREENECT2}>>:KINECT_HAVE_LIBFREENECT2>"
    )

    set(KINECT_BUNDLE_SEARCH_DIRS
        "${FREENECT_LIBRARY_DIR}"
        "${CMAKE_BINARY_DIR}/third_party/libfreenect2/lib"
        "/opt/homebrew/lib"
        "/opt/homebrew/opt/libusb/lib"
        "/opt/homebrew/opt/jpeg-turbo/lib"
    )
    list(FILTER KINECT_BUNDLE_SEARCH_DIRS EXCLUDE REGEX "^$")
    list(JOIN KINECT_BUNDLE_SEARCH_DIRS "|" KINECT_BUNDLE_SEARCH_DIRS_JOINED)

    set(KINECT_APP_EXECUTABLE_NAME "macKinect")
    set(KINECT_APP_BUNDLE_ID "com.mackinect.app")
    set(KINECT_APP_BUNDLE_NAME "macKinect")
    set(KINECT_APP_MINIMUM_SYSTEM_VERSION "12.3")
    configure_file(
        "${CMAKE_SOURCE_DIR}/src/swift/Info.plist.in"
        "${CMAKE_BINARY_DIR}/macKinect-Info.plist"
        @ONLY
    )

    if(APPLE AND KINECT_BUILD_CAMERA_SYSTEM_EXTENSION)
        set(KINECT_CAMERA_EXTENSION_EXECUTABLE_NAME "com.mackinect.app.cameraextension")
        set(KINECT_CAMERA_EXTENSION_BUNDLE_ID "com.mackinect.app.cameraextension")
        set(KINECT_CAMERA_EXTENSION_BUNDLE_NAME "${KINECT_CAMERA_EXTENSION_BUNDLE_ID}.systemextension")
        set(KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME "${KINECT_CAMERA_EXTENSION_BUNDLE_ID}.app")
        set(KINECT_CAMERA_EXTENSION_BUNDLE_VERSION "${KINECT_BUNDLE_VERSION}")
        if(KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID STREQUAL "")
            set(KINECT_CAMERA_EXTENSION_MACH_SERVICE_NAME "${KINECT_CAMERA_EXTENSION_BUNDLE_ID}")
        else()
            set(KINECT_CAMERA_EXTENSION_MACH_SERVICE_NAME "${KINECT_EFFECTIVE_DEVELOPMENT_TEAM_ID}.${KINECT_CAMERA_EXTENSION_BUNDLE_ID}")
        endif()
        configure_file(
            "${CMAKE_SOURCE_DIR}/src/camera_extension/Info.plist.in"
            "${CMAKE_BINARY_DIR}/KinectCameraExtension-Info.plist"
            @ONLY
        )

        add_executable(macKinectCameraExtensionExec
            src/camera_extension/KinectCameraExtensionMain.swift
            src/camera_extension/KinectCameraExtensionProvider.swift
            ${BRIDGE_SOURCES}
        )
        set_target_properties(macKinectCameraExtensionExec PROPERTIES
            Swift_LANGUAGE_VERSION 5
            OUTPUT_NAME "${KINECT_CAMERA_EXTENSION_EXECUTABLE_NAME}"
        )
        target_include_directories(macKinectCameraExtensionExec PRIVATE
            src
        )
        if(FREENECT_INCLUDE_DIR)
            target_include_directories(macKinectCameraExtensionExec PRIVATE ${FREENECT_INCLUDE_DIR})
        endif()
        if(LIBFREENECT2_INCLUDE_DIRS)
            target_include_directories(macKinectCameraExtensionExec PRIVATE ${LIBFREENECT2_INCLUDE_DIRS})
        endif()
        if(KINECT_HAVE_LIBFREENECT)
            target_link_libraries(macKinectCameraExtensionExec PRIVATE ${FREENECT_LIBRARY})
        endif()
        if(KINECT_HAVE_LIBFREENECT2)
            target_link_libraries(macKinectCameraExtensionExec PRIVATE ${LIBFREENECT2_TARGET})
        endif()
        target_link_libraries(macKinectCameraExtensionExec PRIVATE
            "-framework Foundation"
            "-framework CoreMediaIO"
            "-framework CoreMedia"
            "-framework CoreVideo"
            "-framework CoreFoundation"
            "-framework IOKit"
        )
        target_compile_options(macKinectCameraExtensionExec PRIVATE ${SWIFT_BRIDGE_COMPILE_OPTIONS})
        target_compile_definitions(macKinectCameraExtensionExec PRIVATE ${SWIFT_COMMON_COMPILE_DEFINITIONS})
        add_custom_target(macKinectCameraExtensionBundle
            COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_BUNDLE_NAME}"
            COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}/Contents/MacOS"
            COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:macKinectCameraExtensionExec>" "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}/Contents/MacOS/${KINECT_CAMERA_EXTENSION_EXECUTABLE_NAME}"
            COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/KinectCameraExtension-Info.plist" "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}/Contents/Info.plist"
            COMMAND ${CMAKE_COMMAND}
                -DAPP_BUNDLE=${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}
                -DSEARCH_DIRS_PIPE=${KINECT_BUNDLE_SEARCH_DIRS_JOINED}
                -P "${CMAKE_SOURCE_DIR}/cmake/fixup_bundle_only.cmake"
            COMMAND ${CMAKE_COMMAND} -E rename "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_FIXUP_BUNDLE_NAME}" "${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_BUNDLE_NAME}"
            DEPENDS
                macKinectCameraExtensionExec
                "${CMAKE_BINARY_DIR}/KinectCameraExtension-Info.plist"
            VERBATIM
        )
        add_custom_target(macKinectCameraExtension DEPENDS macKinectCameraExtensionBundle)
    endif()

    add_executable(macKinect
        ${SWIFT_SOURCES}
        ${BRIDGE_SOURCES}
        src/bridge/OBSSyphonPublisher.mm
    )

    set_target_properties(macKinect PROPERTIES
        Swift_LANGUAGE_VERSION 5
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${KINECT_APP_BUNDLE_ID}"
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "${KINECT_APP_BUNDLE_NAME}"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${KINECT_APP_BUNDLE_ID}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${KINECT_BUNDLE_VERSION}"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/macKinect-Info.plist"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${KINECT_BUNDLE_VERSION}"
        SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_SOURCE_DIR}/src/bridge/KinectBridge.h"
        XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_SOURCE_DIR}/src/bridge/KinectBridge.h"
    )

    target_include_directories(macKinect PRIVATE
        src
    )
    if(FREENECT_INCLUDE_DIR)
        target_include_directories(macKinect PRIVATE ${FREENECT_INCLUDE_DIR})
    endif()
    if(LIBFREENECT2_INCLUDE_DIRS)
        target_include_directories(macKinect PRIVATE ${LIBFREENECT2_INCLUDE_DIRS})
    endif()

    if(KINECT_HAVE_LIBFREENECT)
        target_link_libraries(macKinect PRIVATE ${FREENECT_LIBRARY})
    endif()
    
    if(KINECT_HAVE_LIBFREENECT2)
        target_link_libraries(macKinect PRIVATE ${LIBFREENECT2_TARGET})
    endif()

    target_link_libraries(macKinect PRIVATE
        "-framework Foundation"
        "-framework AppKit"
        "-framework SwiftUI"
        "-framework AVFoundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework ImageIO"
        "-framework Metal"
        "-framework SystemExtensions"
        "-framework UniformTypeIdentifiers"
    )

    target_compile_options(macKinect PRIVATE ${SWIFT_BRIDGE_COMPILE_OPTIONS})
    target_compile_definitions(macKinect PRIVATE ${SWIFT_COMMON_COMPILE_DEFINITIONS})
    if(TARGET KinectAudioHAL)
        add_dependencies(macKinect KinectAudioHAL)
    endif()
    if(TARGET KinectCameraDAL)
        add_dependencies(macKinect KinectCameraDAL)
        add_custom_command(TARGET macKinect POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/DAL
            COMMAND ${CMAKE_COMMAND} -E copy_directory $<TARGET_BUNDLE_DIR:KinectCameraDAL> $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/DAL/KinectCameraDAL.plugin
            VERBATIM
        )
    endif()
    if(TARGET macKinectCameraExtension)
        add_dependencies(macKinect macKinectCameraExtension)
        add_custom_command(TARGET macKinect POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/Library/SystemExtensions
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/${KINECT_CAMERA_EXTENSION_BUNDLE_NAME} $<TARGET_BUNDLE_DIR:macKinect>/Contents/Library/SystemExtensions/${KINECT_CAMERA_EXTENSION_BUNDLE_NAME}
            VERBATIM
        )
    endif()
    if(KINECT_HAS_APP_PROVISIONING_PROFILE)
        add_custom_command(TARGET macKinect POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${KINECT_APP_PROVISIONING_PROFILE}" $<TARGET_BUNDLE_DIR:macKinect>/Contents/embedded.provisionprofile
            VERBATIM
        )
    endif()

    if(EXISTS "${CMAKE_SOURCE_DIR}/resources/AppIcon.icns")
        add_custom_command(TARGET macKinect POST_BUILD
            # Keep the bundle icon in sync with the repo asset so packaged
            # apps and local smoke-test builds show the same icon in Finder.
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_SOURCE_DIR}/resources/AppIcon.icns" $<TARGET_BUNDLE_DIR:macKinect>/Contents/Resources/AppIcon.icns
            COMMENT "Copying app icon to bundle"
            VERBATIM
        )
    endif()

    if(KINECT_V1_FIRMWARE_PATH)
        if(TARGET KinectAudioHAL)
            add_custom_command(TARGET macKinect POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/HAL
                COMMAND ${CMAKE_COMMAND} -E copy_directory $<TARGET_BUNDLE_DIR:KinectAudioHAL> $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/HAL/KinectAudioHAL.driver
                COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/Resources/libfreenect
                COMMAND ${CMAKE_COMMAND} -E copy_if_different ${KINECT_V1_FIRMWARE_PATH} $<TARGET_BUNDLE_DIR:macKinect>/Contents/Resources/libfreenect/audios.bin
                COMMAND ${CMAKE_COMMAND}
                    -DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:macKinect>
                    -DSEARCH_DIRS_PIPE=${KINECT_BUNDLE_SEARCH_DIRS_JOINED}
                    -DAPP_ENTITLEMENTS_PLIST=${KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST}
                    -DSYSTEM_EXTENSION_ENTITLEMENTS_PLIST=${CMAKE_SOURCE_DIR}/camera_extension_entitlements.plist
                    "-DCODESIGN_IDENTITY=${KINECT_EFFECTIVE_CODESIGN_IDENTITY}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/fixup_mackinect.cmake"
                VERBATIM
            )
        else()
            add_custom_command(TARGET macKinect POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/Resources/libfreenect
                COMMAND ${CMAKE_COMMAND} -E copy_if_different ${KINECT_V1_FIRMWARE_PATH} $<TARGET_BUNDLE_DIR:macKinect>/Contents/Resources/libfreenect/audios.bin
                COMMAND ${CMAKE_COMMAND}
                    -DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:macKinect>
                    -DSEARCH_DIRS_PIPE=${KINECT_BUNDLE_SEARCH_DIRS_JOINED}
                    -DAPP_ENTITLEMENTS_PLIST=${KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST}
                    -DSYSTEM_EXTENSION_ENTITLEMENTS_PLIST=${CMAKE_SOURCE_DIR}/camera_extension_entitlements.plist
                    "-DCODESIGN_IDENTITY=${KINECT_EFFECTIVE_CODESIGN_IDENTITY}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/fixup_mackinect.cmake"
                VERBATIM
            )
        endif()
    else()
        if(TARGET KinectAudioHAL)
            add_custom_command(TARGET macKinect POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/HAL
                COMMAND ${CMAKE_COMMAND} -E copy_directory $<TARGET_BUNDLE_DIR:KinectAudioHAL> $<TARGET_BUNDLE_DIR:macKinect>/Contents/PlugIns/HAL/KinectAudioHAL.driver
                COMMAND ${CMAKE_COMMAND}
                    -DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:macKinect>
                    -DSEARCH_DIRS_PIPE=${KINECT_BUNDLE_SEARCH_DIRS_JOINED}
                    -DAPP_ENTITLEMENTS_PLIST=${KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST}
                    -DSYSTEM_EXTENSION_ENTITLEMENTS_PLIST=${CMAKE_SOURCE_DIR}/camera_extension_entitlements.plist
                    "-DCODESIGN_IDENTITY=${KINECT_EFFECTIVE_CODESIGN_IDENTITY}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/fixup_mackinect.cmake"
                VERBATIM
            )
        else()
            add_custom_command(TARGET macKinect POST_BUILD
                COMMAND ${CMAKE_COMMAND}
                    -DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:macKinect>
                    -DSEARCH_DIRS_PIPE=${KINECT_BUNDLE_SEARCH_DIRS_JOINED}
                    -DAPP_ENTITLEMENTS_PLIST=${KINECT_EFFECTIVE_APP_ENTITLEMENTS_PLIST}
                    -DSYSTEM_EXTENSION_ENTITLEMENTS_PLIST=${CMAKE_SOURCE_DIR}/camera_extension_entitlements.plist
                    "-DCODESIGN_IDENTITY=${KINECT_EFFECTIVE_CODESIGN_IDENTITY}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/fixup_mackinect.cmake"
                VERBATIM
            )
        endif()
    endif()

else()
    message(WARNING "Swift compiler not found. Modern app will not be built.")
endif()
