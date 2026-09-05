# macKinect

macKinect is a native macOS control center for Microsoft Kinect v1 and Kinect v2. It gives you a single app to discover sensors, watch live RGB, infrared and depth streams, capture stills and video, run 3D scans, track bodies with Apple Vision, and optionally publish the Kinect camera and microphone to the rest of macOS. If you prefer a reliable webcam path on modern macOS, it can also stream frames to OBS over Syphon and let OBS expose them as a virtual camera.

This README starts from zero. If you clone this repository on a fresh Mac, follow the steps below in order and you will have a working build.

## Contents

* What the app does
* Requirements
* Quick start from a fresh clone
* Building from scratch in detail
* Running and verifying the build
* How to use the app
* System camera and microphone integration
* The OBS virtual camera path
* Audio firmware for Kinect v1
* Updating an existing clone
* Making a distributable build
* Troubleshooting
* How to contribute
* Licensing and support

## What the app does

* Finds Kinect v1 and Kinect v2 on USB and lets you pick which sensor to open
* Shows live preview for RGB, infrared and depth with Vision overlay when tracking is enabled
* Saves still images in JPEG, PNG or TIFF and records preview video to QuickTime movie files
* Captures scan bundles with color, infrared, depth and point cloud files, and merges scans with iterative closest point registration
* Runs Apple Vision face, body and hand tracking on the RGB stream, fuses depth for 3D positions, and streams results over OSC to VRChat or any OSC listener
* Controls tilt, LED, mirror, exposure, white balance, near mode and IR brightness where the hardware supports it
* Streams live preview frames to OBS through Syphon so OBS can publish them as a system webcam
* Can install optional system components so other macOS apps see a Kinect backed microphone or camera, when signing and provisioning allow it

## Requirements

### Hardware and system

* macOS 12.3 or newer, Apple Silicon or Intel
* Kinect v1 or Kinect v2 sensor with external power supply
* Stable USB connection, and USB 3 for Kinect v2

### Software for building

* Xcode Command Line Tools, which provides clang, Swift and the macOS SDK
* CMake 3.15 or newer
* Ninja is recommended, Make also works
* pkg-config
* libusb
* libjpeg-turbo, often called jpeg-turbo
* git

On macOS the easiest way to get the last four is Homebrew. If you do not use Homebrew, install them with your package manager of choice and make sure they are on PATH and pkg-config can find them.

## Quick start from a fresh clone

If you are in a hurry, these commands go from empty directory to running app, assuming the dependencies below are already available.

```bash
git clone https://github.com/Einnovoeg/macKinect.git
cd macKinect
./run-test.sh
open build-smoke/macKinect.app
```

`run-test.sh` configures with CMake, builds the app, and runs a smoke check that prints `--help`, `--version`, `--list` and `--integration-status`. If that script passes, your toolchain is healthy and you can move on to the detailed steps.

## Building from scratch in detail

This section explains every step so a new machine can get from clone to app without guessing where files should live.

### 1. Install the toolchain

Install Xcode Command Line Tools if you have not already:

```bash
xcode-select --install
```

Install Homebrew from https://brew.sh if you do not have it, then install the build dependencies:

```bash
brew install cmake ninja pkg-config libusb jpeg-turbo
```

Verify the tools are available:

```bash
clang --version
swiftc --version
cmake --version
ninja --version
pkg-config --version
```

### 2. Get the Kinect libraries

This repository does not vendor prebuilt Kinect libraries. You need libfreenect for Kinect v1 and libfreenect2 for Kinect v2. Keep them outside this repository so you can reuse them for other projects.

Pick a location for shared libraries. Any directory you own works, for example `~/dev/kinect-deps` or `~/Library/kinect-deps`. Throughout this guide the placeholder `/path/to` is used to mean whatever directory you choose. Replace it with your real path.

Clone and build libfreenect:

```bash
mkdir -p ~/dev/kinect-deps
cd ~/dev/kinect-deps
git clone https://github.com/OpenKinect/libfreenect.git
mkdir libfreenect/build && cd libfreenect/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
```

Clone and build libfreenect2. This also needs libusb and jpeg-turbo which you already installed:

```bash
cd ~/dev/kinect-deps
git clone https://github.com/OpenKinect/libfreenect2.git
mkdir libfreenect2/build && cd libfreenect2/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
```

You do not need to install either library system wide. The macKinect build will find them if you point CMake at their source directories.

If you prefer to keep the libraries somewhere else, just remember the two directories that contain the built libraries and the `include` folders. You will pass them to the next step.

### 3. Clone macKinect and configure

```bash
cd ~
git clone https://github.com/Einnovoeg/macKinect.git
cd macKinect
```

Configure with CMake. If your libfreenect checkouts live in a custom place, pass their locations. If you built them in the default search paths, you can omit the `-D...ROOT` flags and CMake will try to find them automatically.

```bash
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLIBFREENECT_ROOT=/path/to/libfreenect \
  -DKINECT_LIBFREENECT2_ROOT=/path/to/libfreenect2
```

Replace `/path/to/libfreenect` and `/path/to/libfreenect2` with the real directories that contain the libfreenect sources you just built. For example, if you used `~/dev/kinect-deps`, the flags would be `-DLIBFREENECT_ROOT=$HOME/dev/kinect-deps/libfreenect` and `-DKINECT_LIBFREENECT2_ROOT=$HOME/dev/kinect-deps/libfreenect2`.

If configuration succeeds, CMake prints a summary that includes whether Kinect v1 and v2 support are enabled and which SDK was used.

### 4. Build the app

```bash
cmake --build build-control-center --target macKinect -j4
```

When the build finishes, the app bundle is at `build-control-center/macKinect.app`. CMake also copies required dylibs into the bundle, fixes rpaths, and ad hoc signs the result so it can run locally.

## Running and verifying the build

Launch the app from Finder or from Terminal:

```bash
open build-control-center/macKinect.app
```

Or run the binary directly to see command line options:

```bash
build-control-center/macKinect.app/Contents/MacOS/macKinect --help
build-control-center/macKinect.app/Contents/MacOS/macKinect --version
build-control-center/macKinect.app/Contents/MacOS/macKinect --list
build-control-center/macKinect.app/Contents/MacOS/macKinect --integration-status
```

* `--list` prints connected Kinect devices
* `--integration-status` reports whether the audio HAL, camera DAL, camera extension and OBS virtual camera are installed or published, and explains what needs approval

The included smoke test runs the same checks:

```bash
./run-test.sh
```

This test does not require a Kinect to be plugged in. It confirms that CMake can configure, the app builds, and the binaries run without crashing.

## How to use the app

The main window has a left control panel and a right preview panel.

### Control panel

The control panel has five workspaces, switched with the segmented control at the top:

* **Control** for connecting to a sensor and starting a stream. Pick a device in Quick Connect or the Control Center card, click Connect, choose the preview stream type, and then Start Stream. This tab also holds two prominent cards that are always visible: OBS Virtual Camera with a Launch button and status badges, and Microphone with the direct Kinect microphone toggle and level meter.
* **Capture** for still and video settings. Use the preview toolbar on the right to capture. This panel only changes output format and quality. Recent captures can be revealed in Finder.
* **Tracking** for Apple Vision. Turn on Enable Tracking and choose Face, Body Pose or Hand Pose. When tracking is on, the app runs Vision on each RGB frame and, when depth is available, lifts 2D detections into 3D meter space. Results are drawn over the preview and can be sent over OSC.
* **Hardware** for camera and motor controls such as Mirror, Auto Exposure, Auto White Balance, Near Mode, tilt angle, LED mode, manual exposure and IR brightness. The direct microphone control was moved to Control for quicker access, so this panel shows a note that points there.
* **System** for system integration status and actions. It shows Camera Route and Microphone Route badges, publish toggles, and buttons to install integration, re-check status, apply shared settings or release hardware.

At the top of the left panel a header card shows connection status, a Quick Connect picker, and a two by two grid with Device, Stream, Mic and System summaries. The footer at the very bottom of the window shows the app version and a short description.

### Preview panel

The preview panel shows:

* A stream selector and Capture Image and Record Video buttons at the top
* The live video with small status badges overlaid in the corner, such as Connected, Streaming RGB or REC
* A bottom row with Mic, Scanner, DAL and HAL tiles that summarize system state
* When tracking is enabled and Show Overlay is on, face boxes and body joints are drawn on top of the RGB image

Use the stream selector to switch between RGB, infrared and depth. Tracking works best with RGB. Infrared preview is converted to RGB for display so Vision can still run on it.

## System camera and microphone integration

macKinect can optionally make the Kinect available to other macOS apps. This is separate from the live preview inside macKinect.

There are three pieces:

* **KinectAudioHAL.driver** is a CoreAudio HAL plugin that publishes a Kinect microphone to the system. It works best with Kinect v1, which actually has a microphone array. Kinect v2 has no microphone in the current backend.
* **KinectCameraDAL.plugin** is a legacy CoreMediaIO DAL plugin. It is a fallback for older macOS versions and is blocked by security policy on macOS 12.1 and newer on many machines.
* **com.mackinect.app.cameraextension.systemextension** is the modern Camera Extension. This is the preferred camera path, but it only activates when the app is signed with a valid Apple Developer certificate and a provisioning profile that includes the System Extension capability, and after the user approves it in System Settings under General, Login Items and Extensions, Camera Extensions.

On an ad hoc signed build, the DAL and HAL can still be installed to your user library and the app will suggest using OBS Virtual Camera as the practical webcam path.

To install:

* Open the System workspace in the app and click Install Integration, then approve the privileged install prompt. The installer stages copies to a secure temporary directory, fixes rpaths for bundled libraries, signs the bundles, verifies with `codesign --verify`, and then copies them to system locations.
* Or run `./install-system-integration.sh` from Terminal.

To check status, look at the badges in the System tab or run:

```bash
build-control-center/macKinect.app/Contents/MacOS/macKinect --integration-status
```

If you turn on Publish to macOS Apps, the app releases its direct connection so the system plugins can claim the sensor. Turn that off again when you want to preview inside macKinect.

## The OBS virtual camera path

On macOS 13 and newer, the most reliable way to use Kinect video as a webcam is through OBS. macKinect publishes preview frames to OBS over Syphon, and OBS exposes its virtual camera to the system.

1. Install OBS from https://obsproject.com and make sure it is in `/Applications/OBS.app`.
2. In macKinect, open the Control tab and click Launch OBS Virtual Camera. This creates an OBS scene collection named macKinect with a single Syphon source called Kinect Camera, centered at 1920 by 1080 with scale inner so the whole frame is visible, and then launches OBS with `--startvirtualcam`.
3. Keep the Kinect preview streaming in macKinect so OBS keeps receiving frames.
4. In any other app that asks for a camera, choose OBS Virtual Camera.

You can also open the OBS scene collection manually at `~/Library/Application Support/obs-studio/basic/scenes/macKinect.json` to confirm the source is centered. If video appears flipped or cropped, check that the Syphon source bounds are 1920 by 1080 and that the source is aligned to the center.

## Audio firmware for Kinect v1

Kinect v1 audio needs a firmware file called `audios.bin`. This file is not included in the repository and is not redistributed with release builds unless you have verified you have the right to do so.

If you have the file, place it at `firmware/audios.bin` inside the cloned repository before building, or at `Contents/Resources/libfreenect/audios.bin` inside the built app bundle. The build and install scripts will stage it into the HAL bundle when present. Without it, audio will show as unavailable and the direct microphone toggle will stay off. Kinect v2 has no audio path in the current backend, so it will always show as unavailable.

See `DEPENDENCIES.md` for the full user supplied dependency note.

## Updating an existing clone

When you want to pull in new changes:

```bash
cd macKinect
git pull
```

If dependencies changed, rebuild them first, then rebuild the app:

```bash
cmake -S . -B build-control-center -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLIBFREENECT_ROOT=/path/to/libfreenect \
  -DKINECT_LIBFREENECT2_ROOT=/path/to/libfreenect2
cmake --build build-control-center --target macKinect -j4
```

If you changed the `VERSION` file or switched branches, delete the old build folder first to avoid stale Info.plist caching:

```bash
rm -rf build-control-center
```

Then configure and build again as above.

## Making a distributable build

For a release style bundle that you can copy to another Mac:

```bash
./package-app.sh
```

This writes a DMG and a ZIP to `dist/` and a SHA256 checksum next to them. It signs the bundle if `MACOS_SIGN_IDENTITY` is set, otherwise it ad hoc signs. For a fully signed installer package, also set `MACOS_PKG_SIGN_IDENTITY` and run `./package-installer.sh`.

Ad hoc signed builds run locally, but system extension activation and notarization require a real Apple Developer identity and provisioning.

## Troubleshooting

* **No Kinect detected** Make sure the sensor has external power, the USB cable is firmly seated, and try a different port. Kinect v2 must be on USB 3. Run `build-control-center/macKinect.app/Contents/MacOS/macKinect --list` to see if the backend finds anything at all.
* **Stream will not start** If Publish to macOS Apps is on, turn it off. That toggle hands the sensor to the system plugins and macKinect will not open it at the same time. Also try Refresh Devices and reconnect.
* **Microphone stays off** Kinect v1 needs `audios.bin` in the right place. Kinect v2 has no microphone in this backend. Make sure the sensor is connected and streaming before toggling the microphone.
* **Camera extension shows Bundled but not Active** This is expected on ad hoc builds. It needs a paid Apple Developer program membership, a Camera Extension entitlement, and user approval in System Settings. Until then, use OBS Virtual Camera.
* **Build fails with missing libfreenect** CMake is not finding your checkouts. Pass `-DLIBFREENECT_ROOT` and `-DKINECT_LIBFREENECT2_ROOT` with absolute paths to the source directories, not the `build` subfolders, and delete the old build folder before reconfiguring.
* **Swift compiler cannot load standard library** Your Command Line Tools SDK is out of sync with the Swift toolchain. Run `xcode-select --install` again or set `SDKROOT` to the SDK that matches your tools, for example `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
* **`codesign --verify` fails with unsealed contents** Delete Finder metadata with `xattr -cr` on the bundle and rebuild. The package scripts already do this.

If you hit a bug that is not listed here, please open an issue with macOS version, Kinect model, how you built, and the output of `--integration-status`.

## How to contribute

This is a hardware project and real device testing is the most valuable contribution.

* Try different Kinect models and macOS versions and report what works
* Test camera extension activation and microphone publishing end to end
* Try 3D scans and suggest ICP tuning improvements
* Compare tracking accuracy on RGB versus infrared
* If you fix something, please upstream it rather than keeping a local workaround

Before you contribute code, read `CONTRIBUTORS.md` and `THIRD_PARTY_NOTICES.md` so attribution stays correct.

## Licensing

First party project code is released under the MIT License, see `LICENSE`.

Bundled runtime libraries and any optional third party source checkouts keep their own licenses. See `THIRD_PARTY_NOTICES.md`, `DEPENDENCIES.md` and the `licenses` directory for libusb under LGPL 2.1 and libjpeg-turbo under IJG, BSD and zlib terms.

## Support

If this project is useful, you can support the maintainer at https://buymeacoffee.com/einnovoeg.

Support links are also listed in `README.md`, `CONTRIBUTORS.md` and `.github/FUNDING.yml`.
