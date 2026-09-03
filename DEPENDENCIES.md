# Dependencies

This file lists the dependencies required to build, run, package, or redistribute `macKinect`.

## Build Dependencies

### Required

- macOS 12.3 or newer
- Xcode Command Line Tools (`xcode-select --install`)
- CMake 3.15 or newer
- Apple Clang with C++17 support
- Swift toolchain from Xcode (Swift 5+)
- `libusb` (1.0)
- `jpeg-turbo` (libjpeg-turbo)
- `pkg-config`

### Recommended

- `ninja` for faster builds
- `gh` if you want to publish GitHub releases from the command line
- `openssl` for team-identifier auto-detection in CMake

## Homebrew Example

```bash
brew install cmake ninja pkg-config libusb jpeg-turbo gh openssl
```

## Optional Local Source Checkouts

These third-party source trees can be checked out locally and used directly by the build. For reusable libraries, keep them in a centralized location outside the repo:

```bash
# Recommended shared location:
/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect
/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect2
```

The repo contains symlinks `libfreenect -> /Volumes/Mac Stick/Library/kinect-deps/libfreenect` and `libfreenect2 -> /Volumes/Mac Stick/Library/kinect-deps/libfreenect2` already ignored by git. Their license obligations are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

If you keep those local source trees in a shared library location outside the repo, pass their paths into CMake:

```bash
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLIBFREENECT_ROOT=/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect \
  -DKINECT_LIBFREENECT2_ROOT=/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect2
```

## Optional Runtime Dependencies

### OBS.app

OBS is optional, but recommended if you want the most reliable current webcam path through OBS Virtual Camera.

- Download: https://obsproject.com/
- After install, `macKinect` → System → Launch OBS Virtual Camera
- Requires Syphon.framework bundled inside OBS.app (loaded lazily via `OBSSyphonPublisher.mm`)

### Kinect v1 `audios.bin`

Kinect v1 microphone support depends on `audios.bin`.

- Treat it as a user-supplied firmware dependency stored in `firmware/audios.bin` (gitignored).
- Do not assume this repository grants redistribution rights for that blob.
- If you provide it locally for development, keep it outside git-tracked release content unless you have verified licensing for redistribution.
- The installer will stage it into `KinectAudioHAL.driver/Contents/Resources/libfreenect/audios.bin` when present.
- If missing, the HAL logs `firmware directory not found` and direct mic remains unavailable; system HAL will report no mic.

### Apple Vision & VRChat OSC

- Tracking uses Apple Vision (`VNDetectFaceLandmarksRequest`, `VNDetectHumanBodyPoseRequest`) — no extra install.
- VRChat OSC export sends UDP to `127.0.0.1:9000` by default; configure host/port in the Tracking workspace.

## Optional Signing/Packaging Requirements

These are only required when you need the modern camera-extension path or signed redistributable packages:

- Apple Developer code-signing identity (auto-detected via `security find-identity -v -p codesigning` if single Apple Development cert exists)
- Apple development team identifier (OU field, auto-derived via `openssl x509 -noout -subject`)
- Provisioning profile with the System Extension capability for Camera Extension activation (`KINECT_APP_PROVISIONING_PROFILE`)
- `pkgbuild` signing identity if you distribute signed `.pkg` installers (`MACOS_PKG_SIGN_IDENTITY`)

Without these, the app builds ad-hoc (`-`) and system HAL/DAL will be ignored by macOS. Use OBS Virtual Camera as fallback; `install-system-integration.sh` will warn instead of failing.

## Runtime Libraries That May Be Bundled In Release Artifacts

The packaging flow may bundle these runtime libraries into the app and plugin bundles when they are linked into the build (via `install_name_tool` rpath fixups):

- `libusb` (LGPL-2.1, see `licenses/libusb/COPYING`)
- `libturbojpeg` (IJG + BSD + zlib, see `licenses/libjpeg-turbo/LICENSE.md`)
- `libfreenect` (Apache 2.0 / GPL 2.0, see `libfreenect/APACHE20`, `libfreenect/GPL2`)
- `libfreenect2` (Apache 2.0 / GPL 2.0, see `libfreenect2/APACHE20`, `libfreenect2/GPL2`)

When redistributing packaged binaries, include the notices and license files listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Preserve upstream copyright headers and, for non-git redistributions of `libfreenect` source, include the contributor list per upstream `CONTRIB`.
