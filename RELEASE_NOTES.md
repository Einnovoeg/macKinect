# Release Notes

## macKinect 1.0

Release date: 2026-04-12

### Highlights

- Native macOS Kinect control center for Kinect v1 and Kinect v2
- Live RGB, infrared, and depth preview with still and video capture
- Simple scan bundle export with point-cloud output
- System microphone and camera integration paths, with OBS Virtual Camera fallback for practical webcam use
- Public repository cleanup for licensing, privacy, packaging, and release documentation
- First-party app icon integrated into the app bundle and packaged release assets

### Verification summary

This release was verified with:

- successful CMake configure
- successful `macKinect` app build
- successful CLI smoke tests:
  - `--help`
  - `--version`
  - `--list`
  - `--integration-status`
- fresh first-party PII scan
- fresh release packaging pass
- verified app icon bundle metadata and installed app copy

### Known limitations

- Camera Extension activation still depends on valid Apple signing, entitlements, provisioning, and user approval
- DAL publishing remains a compatibility fallback and is not reliable on all modern macOS versions
- Kinect v1 image-control writes are disabled on current macOS builds because the underlying `libfreenect` control-transfer path can crash in `libusb`
- Kinect v1 audio still requires a user-supplied `audios.bin` firmware blob
- The `.pkg` wrapper remains unsigned unless `MACOS_PKG_SIGN_IDENTITY` is configured during packaging
- Hardware-dependent features still need broader real-device validation

### Help wanted

If you use this release and find a bug, please open an issue or a fix. The project especially needs help with camera-extension activation, system microphone validation, Kinect v1 control stability, and better scanner reconstruction quality.
