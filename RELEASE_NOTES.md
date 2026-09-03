# Release Notes

## macKinect 1.1

Release date: 2026-09-03

### Highlights

- Native macOS Kinect control center for Kinect v1 and Kinect v2
- Live RGB, infrared, and depth preview with still and video capture + Vision overlay
- Simple scan bundle export with point-cloud output + full ICP registration
- Apple Vision 3D skeletal tracking with VRChat OSC export (RGB+IR, depth-fused)
- System microphone and camera integration paths, with OBS Virtual Camera fallback for practical webcam use
- Stable left-panel layout: no more text moving/shrinking when app is open
- Public repository cleanup for licensing, privacy, packaging, and release documentation
- First-party app icon integrated into the app bundle and packaged release assets

### What changed in 1.1

- Fixed left-panel jitter (`ContentView.swift`): fixed `infoTile` height, disabled implicit 30Hz animations, bounded status text, stabilized picker
- Replaced flat point-cloud concatenation with ICP (50 iter, KD-tree, centroid pre-align) in `PointCloudMerger.swift`
- Resolved Kinect v1 `libusb` crashes (motor subdevice excluded, audio subdevice correctly claimed)
- Enabled image controls (Mirror, Exposure, White Balance, Near Mode, IR Brightness) for both v1 and v2
- Added Vision tracking pipeline + `KinectScanner`/`TrackingService`/`OSCTrackerSender` modules
- Added detailed coordinator/security comments in `KinectManager.swift` and `ContentView.swift`
- Centralized reusable libs to `/Volumes/Mac Stick/Library/kinect-deps` (symlinked, gitignored)
- Rewrote `README.md` / `DEPENDENCIES.md` for centralized-deps and ICP; updated `.gitignore`

### Verification summary

This release was verified with:

- successful CMake configure (auto-detected signing identity/team if single Apple Development cert)
- successful `macKinect` app build (`build-control-center`)
- successful CLI smoke tests:
  - `--help`
  - `--version`
  - `--list`
  - `--integration-status`
- fresh first-party PII scan (no emails/usernames, only `buymeacoffee.com/einnovoeg`)
- fresh third-party license audit (libusb LGPL-2.1, libjpeg-turbo IJG/BSD, libfreenect/libfreenect2 Apache2/GPL2, credits preserved)
- verified app icon bundle metadata and installed app copy in `/Users/einnovoeg/Applications`

### Known limitations

- Camera Extension activation still depends on valid Apple signing, entitlements, provisioning, and user approval (see `DEPENDENCIES.md`); use OBS Virtual Camera until `systemextensionsctl list` shows `*[activated enabled]`
- DAL publishing remains a compatibility fallback and is blocked by macOS 12.1+ on many builds
- Kinect v1 audio still requires a user-supplied `audios.bin` firmware blob (`firmware/audios.bin`, gitignored)
- ICP registration is implemented but benefits from further tuning on real scans
- The `.pkg` wrapper remains unsigned unless `MACOS_PKG_SIGN_IDENTITY` is configured during packaging
- Hardware-dependent features still need broader real-device validation

### Help wanted

If you use this release and find a bug, please open an issue or a fix. The project especially needs help with camera-extension activation, system microphone validation, further ICP tuning, and tracking accuracy on IR vs RGB. Do not silently work around issues — upstream a fix!

---

## macKinect 1.0

Release date: 2026-04-12

### Highlights

- Native macOS Kinect control center for Kinect v1 and Kinect v2
- Live RGB, infrared, and depth preview with still and video capture
- Simple scan bundle export with point-cloud output
- System microphone and camera integration paths, with OBS Virtual Camera fallback for practical webcam use
- Public repository cleanup for licensing, privacy, packaging, and release documentation
- First-party app icon integrated into the app bundle and packaged release assets

### Verification summary (1.0)

- successful CMake configure
- successful `macKinect` app build
- CLI smoke tests: `--help`, `--version`, `--list`, `--integration-status`
- PII scan, license audit, packaging, icon verification

### Known limitations (1.0)

- Camera Extension activation still depends on valid Apple signing, entitlements, provisioning, and user approval
- DAL publishing remains a compatibility fallback and is not reliable on all modern macOS versions
- Kinect v1 image-control writes are disabled on current macOS builds because the underlying `libfreenect` control-transfer path can crash in `libusb`
- Kinect v1 audio still requires a user-supplied `audios.bin` firmware blob
- The `.pkg` wrapper remains unsigned unless `MACOS_PKG_SIGN_IDENTITY` is configured during packaging
- Hardware-dependent features still need broader real-device validation
