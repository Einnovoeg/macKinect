# Release Notes

## macKinect 1.1.2

Release date: 2026-03-29

### Highlights

- Final installer hardening pass so privileged staging respects `TMPDIR`
- Fresh smoke verification and privacy scan on the current repo state
- Updated release packaging and metadata for a new GitHub release

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
