# macKinect

`macKinect` is a native macOS control center for Microsoft Kinect v1 and Kinect v2 sensors. It provides live RGB, infrared, and depth preview, still and video capture, simple 3D scan export, Apple Vision-based skeletal tracking with VRChat OSC export, and optional system-level microphone and camera integration paths for macOS.

## What this project does

- Opens Kinect v1 and Kinect v2 devices from a native macOS app
- Shows live `RGB`, `Infrared`, and `Depth` preview streams with Vision overlay
- Saves still images and preview video (QuickTime/H.264)
- Exports a scan bundle with `color.ppm`, `infrared.pgm`, `depth_mm.pgm`, and `scan.ply`
- Performs ICP + centroid registration for multi-frame point-cloud assembly
- Tracks faces/bodies via Apple Vision, fuses Kinect depth for 3D meter-space poses, streams to VRChat via UDP OSC
- Publishes the Kinect microphone through a CoreAudio HAL plugin when installed and signed correctly
- Publishes the camera through a Camera Extension when properly provisioned, with DAL and OBS Virtual Camera fallback paths where needed

## What works today

- Device discovery for Kinect v1 and Kinect v2 (libfreenect / libfreenect2)
- App-side preview, capture, recording, and scanner flows
- Image controls (Mirror, Auto Exposure, Auto White Balance, Near Mode, Manual Exposure, IR Brightness) for both v1 and v2
- Kinect v1 audio (requires `audios.bin`) without crashing on Apple Silicon (motor subdevice excluded, audio subdevice correctly claimed)
- Tracking on both RGB and IR streams (IR converted via `grayscaleToRGB`)
- System integration packaging for:
  - `KinectAudioHAL.driver`
  - `KinectCameraDAL.plugin`
  - `com.mackinect.app.cameraextension.systemextension`
- OBS Virtual Camera fallback workflow via Syphon
- Stable left-panel layout (fixed `infoTile` height, disabled implicit 30Hz animations, bounded status text)
- Basic smoke verification through `./run-test.sh`

## What does not work reliably yet

- Camera Extension activation still depends on correct Apple signing, entitlements, provisioning, and user approval in System Settings → General → Login Items & Extensions
- Legacy DAL publishing is only a compatibility fallback and is blocked by macOS 12.1+ security policies on many builds
- Kinect v1 audio still depends on a user-supplied `audios.bin` firmware blob (not redistributed)
- `.pkg` installer signing still depends on a separate installer-signing identity if you want a fully signed wrapper for redistribution
- ICP registration is implemented but benefits from further tuning and broader real-world scan testing
- Hardware-dependent features cannot be fully validated without a real sensor connected
- No automated CI hardware test; camera/mic system tests require manual `coreaudiod` / `VDCAssistant` restart

## Help wanted

If you use this repository and hit a bug, please report it or open a fix. The fastest way to improve this project is more real hardware testing across different macOS versions, code-signing setups, and Kinect models.

If you can help, the highest-value areas are:

- Camera Extension activation and end-to-end webcam publishing
- System microphone validation across macOS versions
- Further ICP tuning and scanner reconstruction quality
- Tracking accuracy on IR vs RGB, and VRChat OSC interoperability

Please do not silently work around issues locally if you can upstream a fix or at least document the failure mode. Every issue report helps!

## Requirements

### Runtime

- macOS 12.3 or newer
- Kinect v1 or Kinect v2 hardware
- External power supply for the Kinect
- Stable USB connection
- USB 3 for Kinect v2

### Build dependencies

- Xcode Command Line Tools
- CMake 3.15 or newer
- Apple Clang with C++17 support
- Swift toolchain from Xcode
- `libusb`
- `jpeg-turbo`
- `pkg-config`
- `ninja` recommended

Dependency details are documented in [DEPENDENCIES.md](DEPENDENCIES.md).

## Install and run

### Quick smoke test

```bash
./run-test.sh
```

### Manual build

```bash
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-control-center --target macKinect -j4
```

Shared library location (recommended for reusable deps):

```bash
# Library files used by multiple apps should live in a centralized location:
# /Volumes/Mac Stick/Library/kinect-deps/
# The repo already symlinks libfreenect/libfreenect2 there.
# Pass explicit roots if your checkouts live elsewhere:
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLIBFREENECT_ROOT=/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect \
  -DKINECT_LIBFREENECT2_ROOT=/Volumes/Mac\ Stick/Library/kinect-deps/libfreenect2
```

### Launch the app

```bash
open build-control-center/macKinect.app
```

### Useful CLI checks

```bash
build-control-center/macKinect.app/Contents/MacOS/macKinect --help
build-control-center/macKinect.app/Contents/MacOS/macKinect --version
build-control-center/macKinect.app/Contents/MacOS/macKinect --list
build-control-center/macKinect.app/Contents/MacOS/macKinect --integration-status
```

## System integration

`macKinect` can install optional system components so other macOS apps can see Kinect-backed devices:

- `KinectAudioHAL.driver` for microphone publishing
- `KinectCameraDAL.plugin` as a legacy camera fallback
- `com.mackinect.app.cameraextension.systemextension` as the preferred modern camera path when valid Apple signing and provisioning are available

Use the **System** workspace inside the app or run:

```bash
./install-system-integration.sh
```

The installer stages writable copies of the plugins via secure `mktemp` directories (respecting `TMPDIR`), fixes `rpath` with `install_name_tool`, signs them, verifies with `codesign --verify`, and then installs them into system locations with administrator approval. Shell paths are escaped with `shellQuote` to prevent injection.

## OBS camera fallback

On current macOS builds, the most reliable webcam route is still OBS Virtual Camera. `macKinect` can publish preview frames to OBS over Syphon, and OBS can then expose that feed as a webcam.

Expected setup:

1. Install OBS.app.
2. Open the **System** workspace inside `macKinect`.
3. Use **Launch OBS Virtual Camera**.
4. Keep the Kinect preview running so OBS receives frames.

## Kinect v1 audio firmware

Kinect v1 audio support still depends on `audios.bin`. This repository does not treat that firmware blob as first-party project content.

- Local development builds may use a user-supplied `audios.bin`
- Release artifacts should not redistribute that blob unless you have independently confirmed redistribution rights
- See [DEPENDENCIES.md](DEPENDENCIES.md) for the user-supplied dependency note
- The app will stage `firmware/audios.bin` into the HAL bundle when present

## Verification

`./run-test.sh` verifies:

- CMake configure succeeds
- `macKinect` builds successfully
- `macKinect --help` runs
- `macKinect --version` runs
- `macKinect --list` runs cleanly
- `macKinect --integration-status` runs cleanly

This is a smoke test, not a full hardware certification pass.

## Privacy and repository hygiene

First-party project files are kept free of machine-specific absolute paths, local usernames, email addresses, and other personally identifiable information unless a third-party notice requires attribution. Third-party source trees keep their upstream notices and licenses intact. Local-only files (`AGENTS.md`, `session*.md`) are excluded via `.gitignore`.

## Licensing

First-party project code is released under the [MIT License](LICENSE).

Bundled runtime libraries and optional third-party source checkouts keep their own licenses. See:

- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- [DEPENDENCIES.md](DEPENDENCIES.md)
- `licenses/` (libusb LGPL-2.1, libjpeg-turbo IJG/BSD/zlib)

## Support

If this project is useful, you can support it at [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg).
