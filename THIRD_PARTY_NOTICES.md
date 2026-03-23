# Third-Party Notices

`macKinect` relies on third-party software for Kinect access, optional camera routing, and some packaged runtime libraries. This file documents the components that are part of the build or release path, preserves required credit, and points to the license material that must accompany redistribution.

## First-Party License

First-party project code in this repository is released under the [MIT License](LICENSE).

Third-party components listed below keep their original licenses and notices.

## Optional Local Kinect Source Checkouts

### OpenKinect `libfreenect`

- Upstream project: [OpenKinect/libfreenect](https://github.com/OpenKinect/libfreenect)
- Local checkout path when used for development: `libfreenect/`
- Purpose in this project: Kinect v1 device access, including RGB, depth, motor, LED, and audio support
- Upstream credit: OpenKinect community, including maintainers and contributors credited by upstream such as Hector Martin, Joshua Blake, and Kyle Machulis
- License model: dual-licensed under Apache License 2.0 or GPL 2.0
- Local license texts:
  - `libfreenect/APACHE20`
  - `libfreenect/GPL2`

Important note: the upstream `libfreenect/CONTRIB` file states that non-git redistributions of the source should include a contributor list valid for the exact upstream revision used. If you redistribute a checked-out `libfreenect` source snapshot outside of git, satisfy that requirement in addition to shipping the upstream license texts and preserving source headers.

### OpenKinect `libfreenect2`

- Upstream project: [OpenKinect/libfreenect2](https://github.com/OpenKinect/libfreenect2)
- Local checkout path when used for development: `libfreenect2/`
- Purpose in this project: Kinect v2 device access, including RGB, IR, and depth streaming
- Upstream credit: OpenKinect contributors and maintainers, including contributors credited by upstream such as Joshua Blake, Florian Echtler, Christian Kerl, and Lingzhu Xiang
- License model: dual-licensed under Apache License 2.0 or GPL 2.0
- Local license texts:
  - `libfreenect2/APACHE20`
  - `libfreenect2/GPL2`

## Runtime Libraries Commonly Bundled Into Release Artifacts

### `libusb`

- Upstream project: [libusb](https://libusb.info/)
- Purpose in this project: USB device communication
- Observed local package during current development: `libusb 1.0.29`
- License: GNU Lesser General Public License 2.1 or later
- Local license copy:
  - `licenses/libusb/COPYING`

### `libjpeg-turbo`

- Upstream project: [libjpeg-turbo](https://libjpeg-turbo.org/)
- Purpose in this project: JPEG/TurboJPEG support required by `libfreenect2`
- Observed local package during current development: `libjpeg-turbo 3.1.3`
- License family: IJG license plus Modified BSD, with zlib terms for specific portions as documented by upstream
- Local license copy:
  - `licenses/libjpeg-turbo/LICENSE.md`

## Optional Non-Bundled Runtime Integrations

### OBS + Syphon

- Purpose in this project: optional webcam fallback via OBS Virtual Camera and Syphon publishing
- Integration model: `macKinect` dynamically loads `Syphon.framework` from the user's local OBS.app installation when available
- Redistribution status: not bundled or redistributed by this repository's release artifacts unless explicitly added downstream
- Upstream references:
  - [OBS Studio](https://github.com/obsproject/obs-studio)
  - [Syphon](https://syphon.info/)

## User-Supplied Firmware

### Kinect v1 `audios.bin`

`audios.bin` may be required for Kinect v1 audio features, but it is treated as a user-supplied dependency, not first-party project content.

- Do not assume this repository grants redistribution rights for that blob.
- Do not ship it in release artifacts unless you have independently confirmed that redistribution is permitted.

## Redistribution Checklist

If you distribute binaries produced from this repository:

1. Include [LICENSE](LICENSE) for first-party code.
2. Include this notice file.
3. Include the upstream license texts listed above.
4. Preserve copyright and attribution notices already present in any third-party code you bundle or check out locally.
5. If you redistribute a `libfreenect` source snapshot outside git, satisfy the contributor-list requirement described in upstream `CONTRIB`.
6. Do not remove or rewrite required third-party author attributions from upstream material.
