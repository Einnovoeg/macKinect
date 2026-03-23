# macKinect

`macKinect` is a native macOS control center for Microsoft Kinect v1 and Kinect v2 sensors. It provides live RGB, infrared, and depth preview, still and video capture, basic point-cloud export, direct device controls, and optional system-level microphone and camera integration paths for macOS.

## Features

- Unified support for Kinect v1 and Kinect v2 in one macOS app
- Live preview for `RGB`, `Infrared`, and `Depth` streams
- Kinect hardware controls such as tilt, LED mode, mirroring, exposure, white balance, and near mode where supported
- Still-image capture and preview-video recording
- 3D scan bundle export with `color.ppm`, `infrared.pgm`, `depth_mm.pgm`, and `scan.ply`
- Optional CoreAudio HAL microphone publishing for macOS-wide microphone exposure
- Optional camera publishing paths through:
  - bundled Camera Extension when properly signed and provisioned
  - legacy DAL fallback where supported
  - OBS Virtual Camera as the practical webcam fallback on current macOS
- Built-in diagnostics and installer flows for system integration troubleshooting

## Requirements

### Runtime

- macOS 12.3 or newer
- Kinect v1 or Kinect v2 hardware
- Kinect external power supply
- Stable USB connection
- USB 3 for Kinect v2

### Build Dependencies

- Xcode Command Line Tools
- CMake 3.15 or newer
- Apple Clang with C++17 support
- Swift toolchain from Xcode
- `libusb`
- `jpeg-turbo`
- `pkg-config`
- `ninja` recommended

Dependency installation details are listed in [DEPENDENCIES.md](DEPENDENCIES.md).

## Build From Source

### Quick smoke test

```bash
./run-test.sh
```

### Manual build

```bash
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-control-center --target macKinect -j4
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

## System Integration

`macKinect` can install optional system components so other macOS apps can see Kinect-backed devices:

- `KinectAudioHAL.driver` for microphone publishing
- `KinectCameraDAL.plugin` as a legacy camera fallback
- `com.mackinect.app.cameraextension.systemextension` as the preferred camera path when a valid Apple Developer profile and entitlement are available

Use the **System** workspace inside the app or run:

```bash
./install-system-integration.sh
```

The installer stages writable copies of the plugins, fixes library paths, signs them, then installs them into system locations with administrator approval.

## OBS Camera Fallback

On current macOS builds, the most reliable webcam route is still OBS Virtual Camera. `macKinect` can publish preview frames to OBS over Syphon, and OBS can then expose that feed as a webcam.

Expected setup:

1. Install OBS.app.
2. Open the **System** workspace in `macKinect`.
3. Use **Launch OBS Virtual Camera**.
4. Keep the Kinect preview streaming so OBS receives frames.

## Kinect v1 Audio Firmware

Kinect v1 audio support still depends on `audios.bin`. This repository does **not** treat that firmware blob as project-owned content.

- Local development builds may use a user-supplied `audios.bin`.
- Release artifacts should not redistribute that blob unless you have independently confirmed redistribution rights.
- See [DEPENDENCIES.md](DEPENDENCIES.md) for the user-supplied dependency note.

## Packaging A Release

Create a release bundle with:

```bash
./package-app.sh
```

Artifacts are written to `dist/` and are versioned from [VERSION](VERSION).

Supporting release metadata:

- [CHANGELOG.md](CHANGELOG.md)
- [RELEASE_NOTES.md](RELEASE_NOTES.md)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- [DEPENDENCIES.md](DEPENDENCIES.md)
- [LICENSE](LICENSE)

## Verification

`./run-test.sh` verifies:

- CMake configure succeeds
- `macKinect` builds successfully
- `macKinect --help` runs
- `macKinect --version` runs
- `macKinect --list` runs cleanly
- `macKinect --integration-status` runs cleanly

Hardware-dependent features such as live streaming, point-cloud capture, direct microphone input, and system publishing still require a real Kinect sensor plus the relevant macOS permissions and signing setup.

## Privacy And Repository Hygiene

Repo-owned files are kept free of machine-specific absolute paths, local usernames, and personal contact details unless a third-party license notice requires attribution. Third-party source trees keep their upstream credits and license notices intact.

## Licensing

First-party project code is released under the [MIT License](LICENSE).

Bundled runtime libraries and optional third-party source checkouts remain under their own licenses. See:

- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- `libfreenect/` if you keep a local checkout for development
- `libfreenect2/` if you keep a local checkout for development
- `licenses/`

## Support

If this project saves you time, you can support it at [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg).
