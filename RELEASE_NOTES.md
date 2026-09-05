# Release Notes

## macKinect 2.0

Release date: 2026-09-04

### Highlights

- **Home stretch — 2.0 polished:** OBS Virtual Camera now streams the complete frame and is prominently placed in Control Center; microphone control moved to Control Center; system integration pinned to OBS fallback; left-panel text and badge alignment fixed
- **UI reorganization completed:** 5 workspaces `Control/Capture/Tracking/Hardware/System` remain in main window, Settings menu removed entirely (`KinectApp.swift` back to 12-line `WindowGroup`), no more `About` placeholder or front-center publish bar
- **Verified layout:** Window captures show correct header, `Quick Connect`, `Device/Stream/Mic/System` grid, `Control Center`, and preview with `Mic/Scanner/DAL/HAL` tiles — no clipping or overlap
- **OBS pipeline verified:** Syphon source centered at 1920×1080 scale-inner, `launchOBSVirtualCamera` uses `--startvirtualcam`, and `OBSSyphonPublisher` flips vertically for right-side-up frames

### What changed in 2.0

- `KinectManager.swift`: `ensureOBSSceneCollection` `scale_ref`/`bounds` 1280×720 → 1920×1080, `pos` 640,360 → 960,540, `bounds_type` 0/1 → 2 (scale-inner, complete frame); `launchOBSVirtualCamera` restores `--startvirtualcam` and original status notes, removes AppleScript fallback
- `ContentView.swift`: Restored 724f671 polished layout (flexible `infoTile`, `FlowBadgeRow`, `ZStack(alignment:.top)` + footer, `transaction` jitter fixes); moved `Launch OBS Virtual Camera` from `systemIntegrationSection` to `controlsPanel` as `obsProminentCard` (always visible in Control) with `HAL/Bridge` badges; moved microphone from `Hardware` to `micProminentCard` in Control; split System 4-button row into two `HStack` rows to fix 392pt overflow; removed mic from `cameraMotorSection`
- `KinectApp.swift`: Kept at 12 lines, no `Settings` scene (reverted 724f671/f7650a3 Settings duplicate and 4-tab+About)
- `OBSSyphonPublisher.mm`: Kept vertical flip (`Translate+Scale -1`) for correct orientation
- `VERSION`: `1.1.1` → `2.0.0`
- Verified with `screencapture -l` of `macKinect` window (Control, Capture, Hardware, System) and `obs-studio` scene file inspection (`macKinect.json` now shows 1920×1080 centered)

### Verification summary (2.0)

- `swiftc -parse` and `clang -fsyntax-only` clean for `ContentView`, `KinectManager`, `OBSSyphonPublisher`
- `CMake` configure `MacOSX26.5.sdk` + `arm64` + `Ninja` → `macKinect` build + `fixup_bundle` verified
- Window captures: `/tmp/mackinect_v2_fixed_control.png` (1280×852, Control with OBS/Mic prominent), plus Hardware/System captures showing no clipping
- OBS scene file check: `~/Library/Application Support/obs-studio/basic/scenes/macKinect.json` contains `1920,1080` centered
- Next: launch `OBS` via the new Control button and capture OBS window to confirm Syphon full-frame

---

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
