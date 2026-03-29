# Changelog

All notable changes to `macKinect` are documented in this file.

## 1.1.2 - 2026-03-29

- Hardened privileged installer staging further by honoring `TMPDIR` instead of assuming `/tmp` in both the shell installer and the app-driven privileged install flow.
- Re-ran smoke verification, privacy scanning, and release packaging against the current repo state before publishing.
- Refreshed release metadata for a new GitHub release with the current changelog and artifacts.

## 1.1.1 - 2026-03-23

- Hardened the privileged system-integration installer to use secure temporary staging directories, consistent shell safety flags, and post-signature verification before privileged copies.
- Updated the CoreAudio HAL so microphone start now fails fast when Kinect audio capture is not actually ready, instead of publishing a silent-but-apparently-live input.
- Prevented accidental publication of local upstream dependency checkouts and SDK drops by ignoring development-only dependency directories in git.
- Corrected dependency and third-party notice documentation so local `libfreenect` and `libfreenect2` checkouts are described as optional development inputs rather than repo-owned vendored source.
- Fixed `package-installer.sh` so Swift configuration works from repo paths containing spaces by using a clean dedicated build directory and environment-based module-cache configuration.
- Added an explicit packaging guard so the installer script refuses to build misleading ad hoc-signed HAL/DAL packages.

## 1.1.0 - 2026-03-23

- Added a first-party MIT license file and tightened repository-level compliance documentation.
- Reinstated funding metadata and documented the support link in the project docs.
- Expanded the README, dependency inventory, release notes, and redistribution guidance.
- Hardened release packaging so documentation and license materials are shipped with artifacts.
- Marked Kinect v1 `audios.bin` firmware as a user-supplied dependency instead of project-owned release content.
- Continued cleanup of system-integration packaging, signing, and installer behavior.
- Improved the SwiftUI control surface with clearer quick-connect and system-integration affordances plus additional hover help.
- Added more in-code explanatory comments around the GUI update loop, installer staging, and system integration preferences.
- Extended smoke-test verification and release metadata for a GitHub-ready release pass.

## 1.0.0 - 2026-03-14

- Centralized project versioning so the app bundle, system extension, HAL plugin, DAL plugin, packaging script, and release docs all report the same version.
- Improved repo hygiene by removing repo-owned personal support links and machine-specific absolute paths from documentation, UI, and helper scripts.
- Fixed device disconnect handling so the app now closes the active bridge/device session instead of only stopping the stream.
- Normalized capability-driven UI state so stale hardware capability flags do not linger after disconnect or failed connection attempts.
- Sorted discovered devices for a more stable device picker.
- Polished the SwiftUI control center with version display, quick actions, better device summaries, and direct reveal actions for captures and recorded video.
- Added more code comments around preview rendering, bridge/frame ownership, media recording, system integration staging, and point-cloud export.
- Reworked `package-app.sh` to detect local tools, use writable module-cache locations, package project documentation, and include license texts in release artifacts.
- Reworked `run-test.sh` into a real smoke-test script that configures, builds, and exercises the CLI entry points.
- Rewrote the top-level README and added explicit dependency, release, and third-party notice documentation.
