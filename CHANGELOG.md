# Changelog

All notable changes to `macKinect` are documented in this file.

## 1.2.0 - 2026-09-04

- **UI twitching fix (comprehensive):** Isolated 30Hz preview polling via `withTransaction(disablesAnimations:true)`, throttled `audioLevel` (5Hz, quantized 0.1), `recordingVideoSeconds` (4Hz), and `recentDiagnostics` (3Hz) in `KinectManager.swift`; left-panel already had fixed `infoTile` height and `animation(nil)` — now also throttled at source so ScrollView diagnostics no longer relayouts at 30Hz
- **System mic/camera for ad-hoc builds:** HAL firmware search now includes `~/Library/Audio/Plug-Ins/HAL/.../Resources/libfreenect` for user-domain installs; `refreshSystemIntegrationStatus` checks both `/Library` and `~/Library` for HAL/DAL; `installSystemIntegration` no longer blocks on ad-hoc but warns and continues to user-domain fallback; signature-issue messages now suggest OBS Virtual Camera for ad-hoc instead of blocking
- **OBS fallback promoted:** When HAL/DAL ignored due to ad-hoc signing and OBS is installed, system notes now direct to OBS Virtual Camera as reliable path; `systemPublishNote` no longer reports fatal ad-hoc error when OBS available
- **Docs & version:** Bumped `VERSION` to 1.2.0; verified build with Xcode toolchain (`/Volumes/Mac Stick/Applications/Xcode.app`), `codesign --verify`, and CLI smoke tests; rebuilt `build-smoke`/`build-control-center` and copied to `/Users/einnovoeg/Applications`

## 1.1.0 - 2026-09-03

- **GUI polish:** Fixed left-panel text moving/shrinking when app is open
  - Removed `minimumScaleFactor(0.8)` from `infoTile`; fixed tile height 44 with `lineLimit(1)` + truncation + `animation(nil)`
  - Fixed `headerSummarySection` HStack with `fixedSize` + `lineLimit(2,reservesSpace:true)` + `layoutPriority(1)`
  - Stabilized `Quick Connect` picker with explicit width 88, `clipped()`, `fixedSize`; disabled implicit animations for `status`, badges, `LazyVGrid`
  - Added `MARK` comments explaining jitter prevention in `ContentView.swift:174,200`
  - Deleted stale `ContentView.swift.bak*` artifacts
- **3D scan registration:** Replaced centroid-only fallback with full ICP in `PointCloudMerger.swift` (50 iterations, SVD via power iteration, KD-tree, centroid pre-align fallback); added stochastic sampling support and convergence tolerance tuning
- **Kinect v1 stability:** Resolved `libusb_control_transfer` null-handle crash by excluding `FREENECT_DEVICE_MOTOR` from `freenect_select_subdevices()`; fixed `freenect_start_audio` abort by claiming `FREENECT_DEVICE_AUDIO` subdevice
- **Image controls:** Enabled Mirror, Auto Exposure, Auto White Balance, Near Mode, Manual Exposure, IR Brightness for Kinect v1 (`KinectManager.swift:shouldApplyImageControlFlags = currentDevice != nil`); implemented v2 overrides in `freenect_v2_backend.cpp`
- **Vision tracking:** Apple Vision face/body pipeline with depth-fusion to 3D meter-space, overlay rendering on RGB+IR, Tracking workspace, VRChat OSC export (`TrackingService.swift`, `OSCTrackerSender.swift`)
- **Scanner refactoring:** Extracted `KinectScanner.swift` for capture orchestration; added multi-format export (PLY ASCII/Binary, OBJ, XYZ)
- **Code clarity:** Added detailed coordinator docs for `KinectManager` and `SystemExtensionRequestObserver`; documented security model (`shellQuote` + `mktemp` + `codesign --verify` before `ditto` + `trap cleanup`)
- **PII & hygiene:** Redacted team ID email from `session-e808ea68.md`; verified no hardcoded `/Users/` or secrets in first-party sources; `AGENTS.md`/`session*.md`/`.kiro/` excluded via `.gitignore`; added `Kinect/` to ignore (vendored OpenNI ~146M)
- **Docs:** Rewrote `README.md` (ICP, tracking, layout fix, centralized library `/Volumes/Mac Stick/Library/kinect-deps` example); updated `DEPENDENCIES.md` (shared-deps path, OBS/Vision/OSC, signing requirements); updated `.gitignore` (explicit `Kinect/`, icon backups)
- **Library centralization:** Reusable deps remain in `/Volumes/Mac Stick/Library/kinect-deps` (`libfreenect`, `libfreenect2`), symlinked and gitignored
- **Build:** Verified `CMake` configure + `macKinect` build + CLI smoke tests (`--help`, `--version`, `--list`, `--integration-status`) via `run-test.sh`; centralized lib roots auto-respected by CMake
- **Release:** Bumped `VERSION` to 1.1.0; kept v1.0.0 artifacts; prepared for v1.1 GitHub release

## 1.0.0 - 2026-04-12

- Finalized the first public release baseline for the native macOS Kinect control center
- Shipped Kinect v1 and Kinect v2 discovery, preview, capture, and recording in one app
- Shipped 3D scan bundle export with color, infrared, depth, and point-cloud output
- Shipped system integration packaging for the CoreAudio HAL, Camera Extension, and DAL fallback
- Added explicit third-party licensing, dependency, redistribution, and attribution documentation
- Hardened installer staging and signing flows to use secure temporary directories and verification before privileged install
- Cleaned first-party repository content to remove machine-specific paths and personal identifiers
- Preserved the Buy Me a Coffee support link as the only intentional personal link
- Added local-only agent handoff guidance in `AGENTS.md` and excluded it from git
- Fixed a current macOS crash path by disabling unsafe Kinect v1 image-control transfers that can crash inside `libusb`
- Added first-party app icon assets and wired them into the packaged app bundle
- Documented how to build against shared local `libfreenect` / `libfreenect2` checkouts kept outside the repo
- Updated the public documentation to clearly describe what works, what still does not work, and where contributors can help
