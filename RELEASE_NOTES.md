# Release Notes

## macKinect 1.1.1

Release date: 2026-03-23

### Highlights

- Privileged installer hardening for system microphone and camera components
- Safer HAL microphone startup behavior when Kinect audio is unavailable
- Cleaner repo boundary for third-party dependency checkouts and local SDK drops
- Fixed installer packaging from workspace paths that contain spaces
- Continued GUI polish, release metadata cleanup, and redistribution guidance refresh

### Verification Summary

This release is intended to be verified with:

- successful CMake configure
- successful `macKinect` app build
- successful CLI smoke tests:
  - `--help`
  - `--version`
  - `--list`
  - `--integration-status`
- successful packaging through `./package-app.sh`
- successful installer packaging preflight through `./package-installer.sh` with a real Apple signing identity, or an intentional refusal when the build remains ad hoc signed

### Known Limitations

- Hardware features cannot be fully validated without a connected Kinect sensor.
- Kinect v1 audio still requires a user-supplied `audios.bin` firmware blob.
- Camera publishing on modern macOS depends on signing, entitlements, and user approval for the bundled Camera Extension.
- The DAL plugin remains available only as a compatibility fallback where Camera Extension activation is unavailable.
- OBS Virtual Camera remains the most reliable webcam path on current macOS builds.
