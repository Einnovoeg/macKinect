# Dependencies

This file lists the dependencies required to build, run, package, or redistribute `macKinect`.

## Build Dependencies

### Required

- macOS 12.3 or newer
- Xcode Command Line Tools
- CMake 3.15 or newer
- Apple Clang with C++17 support
- Swift toolchain from Xcode
- `libusb`
- `jpeg-turbo`
- `pkg-config`

### Recommended

- `ninja` for faster builds
- `gh` if you want to publish GitHub releases from the command line

## Homebrew Example

```bash
brew install cmake ninja pkg-config libusb jpeg-turbo gh
```

## Optional Local Source Checkouts

These third-party source trees can be checked out locally next to the project and used directly by the build:

- `libfreenect/`
- `libfreenect2/`

They are intentionally ignored by git in this repository so upstream git metadata and local machine history are not published accidentally. Their license obligations are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

If you keep those local source trees in a shared library location outside the repo, pass their paths into CMake:

```bash
cmake -S . -B build-control-center \
  -DLIBFREENECT_ROOT=/path/to/libfreenect \
  -DKINECT_LIBFREENECT2_ROOT=/path/to/libfreenect2
```

## Optional Runtime Dependencies

### OBS.app

OBS is optional, but recommended if you want the most reliable current webcam path through OBS Virtual Camera.

### Kinect v1 `audios.bin`

Kinect v1 microphone support depends on `audios.bin`.

- Treat it as a user-supplied firmware dependency.
- Do not assume this repository grants redistribution rights for that blob.
- If you provide it locally for development, keep it outside git-tracked release content unless you have verified licensing for redistribution.

## Optional Signing/Packaging Requirements

These are only required when you need the modern camera-extension path or signed redistributable packages:

- Apple Developer code-signing identity
- Apple development team identifier
- Provisioning profile with the System Extension capability for Camera Extension activation
- `pkgbuild` signing identity if you distribute signed `.pkg` installers

## Runtime Libraries That May Be Bundled In Release Artifacts

The packaging flow may bundle these runtime libraries into the app and plugin bundles when they are linked into the build:

- `libusb`
- `libturbojpeg`
- `libfreenect`
- `libfreenect2`

When redistributing packaged binaries, include the notices and license files listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
