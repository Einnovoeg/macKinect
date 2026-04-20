# Changelog

All notable changes to `macKinect` are documented in this file.

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
