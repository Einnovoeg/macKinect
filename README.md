# macKinect

Modern Flutter desktop app for Proxmark3, using the Iceman ecosystem with a bundled default core.

## Status

- Cross-platform Flutter UI (currently validated on macOS arm64).
- Bundled core included for first-run use (no Homebrew required for end users).
- Core update/download path from GitHub releases.
- Standard scans + advanced command chaining UI.

## Features

- Preinstalled bundled core.
- Core options in-app:
  - Update current core
  - Download stable core
  - Download experimental core
  - Install local core
  - Add separate core
- Port auto-preference for Iceman-style serial device names (`*usbmodemiceman*` / `*sbmodemiceman*`).
- Read page:
  - HF scan
  - LF scan
  - Continuous HF scan
  - Continuous LF scan
  - EMV scan
- Advanced page:
  - Nested command builder (Group -> Action -> Preset)
  - Command queue/chaining
  - Run single command or full chain

## Build

```bash
flutter pub get
flutter build macos --debug
```

## Run

```bash
flutter run -d macos
```

## Bundle / Refresh Embedded Core

```bash
./tools/bundle_core.sh /opt/homebrew/opt/proxmark3
```

Bundled assets are stored under:

- `assets/bundled/macos/arm64/bin/pm3`
- `assets/bundled/macos/arm64/bin/proxmark3`
- `assets/bundled/macos/arm64/share/proxmark3/*`

## Documentation

- User guide: `USER_GUIDE.md`
- License and third-party notices: `THIRD_PARTY_NOTICES.md`
- Core bundling notes: `tools/README.md`

## Support

- Buy me a coffee: [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg)

## License

This project is licensed under **GNU GPL v3.0 or later**.

See `LICENSE`.

## Inspiration and Compliance Notes

This project references and is inspired by the following open-source projects:

- Proxmark3 core ecosystem: [RfidResearchGroup/proxmark3](https://github.com/RfidResearchGroup/proxmark3)
- UI/UX reference for modern desktop flow: [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI)
- Legacy Qt baseline app in this repository: `src/` (historical Proxmark3GUI implementation)

License context for inspirations:

- `RfidResearchGroup/proxmark3`: GPL-3.0  
  License: [proxmark3/LICENSE.txt](https://github.com/RfidResearchGroup/proxmark3/blob/master/LICENSE.txt)
- `GameTec-live/ChameleonUltraGUI`: MIT  
  License: [ChameleonUltraGUI/LICENSE](https://github.com/GameTec-live/ChameleonUltraGUI/blob/main/LICENSE)
- Legacy repository root (`src/` baseline): LGPL-2.1 text present in repository root `LICENSE`

No source code from the UI reference is copied directly into this repository.  
Bundled Proxmark3 core artifacts remain under their upstream licensing terms.
