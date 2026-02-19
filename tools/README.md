# macKinect tooling

## Bundle a default core (macOS arm64)

Run this after you build or install proxmark3:

```bash
./tools/bundle_core.sh /path/to/pm3
```

You can also point it to an install prefix:

```bash
./tools/bundle_core.sh /path/to/proxmark/install/prefix
```

The script bundles:

- `assets/bundled/macos/arm64/bin/pm3`
- `assets/bundled/macos/arm64/bin/proxmark3` (if available)
- `assets/bundled/macos/arm64/share/proxmark3` (if available)

The app extracts this bundle to application support on first launch and uses it
as the preinstalled core.
