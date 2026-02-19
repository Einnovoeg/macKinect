# Third-Party Notices and License Compliance

This document summarizes third-party components used by macKinect and their license context.

## 1) Core Ecosystem

### RfidResearchGroup / proxmark3

- Project: [https://github.com/RfidResearchGroup/proxmark3](https://github.com/RfidResearchGroup/proxmark3)
- Use in this project:
  - Bundled runtime core artifacts (`pm3`, `proxmark3`, `share/proxmark3`)
  - Command compatibility target for GUI actions
- Upstream license:
  - Declared as GPL-3.0 in upstream repository metadata.
  - License file: [https://github.com/RfidResearchGroup/proxmark3/blob/master/LICENSE.txt](https://github.com/RfidResearchGroup/proxmark3/blob/master/LICENSE.txt)
- Compliance approach:
  - This repository includes the GPLv3 license text in `LICENSE`.
  - Source references and attribution are provided in `README.md`.
  - Bundled core remains under upstream licensing terms.

## 2) UI/UX Inspiration

### GameTec-live / ChameleonUltraGUI

- Project: [https://github.com/GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI)
- Use in this project:
  - UI/UX inspiration only (navigation layout and modern desktop interaction style).
- Upstream license:
  - MIT license (per upstream repository metadata).
  - License file: [https://github.com/GameTec-live/ChameleonUltraGUI/blob/main/LICENSE](https://github.com/GameTec-live/ChameleonUltraGUI/blob/main/LICENSE)
- Compliance approach:
  - No direct source copy from this project is included.
  - Attribution and citation are provided in `README.md`.

## 3) Flutter and Dart Packages (Direct Dependencies)

These are direct `pubspec.yaml` dependencies used by this project:

- `flutter` (Flutter SDK) - BSD-style license
- `intl` - BSD-style license
- `flutter_libserialport` - MIT
- `libserialport` - LGPL-3.0
- `path_provider` - BSD-style license
- `http` - BSD-style license
- `archive` - MIT
- `crypto` - BSD-style license
- `provider` - MIT
- `file_selector` - BSD-style license

License files for these dependencies are available in local pub cache after `flutter pub get`.

## 4) Local Legacy Reference

- Historical Qt implementation included in this repository root (`src/`), used as migration/reference material.
- Repository root currently includes LGPL-2.1 license text (`/LICENSE`) for legacy portions.

## 5) Distribution Notes

- If distributing binaries that include bundled Proxmark3 core, keep attribution and license notices intact.
- If you replace bundled core artifacts, ensure the replacement source and notices are compatible and documented.
- If adding new dependencies, update this file before release.
