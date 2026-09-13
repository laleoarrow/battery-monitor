# Runtime Dock logo resources

These checked-in 512 × 512 PNGs were exported directly from the canonical
`../WattsonGlass.icon` on 2026-09-13 with Apple's Icon Composer `ictool` 1.6
(99.1). They match the reviewed final native exports byte for byte. No raster
editing, resizing, AI generation, or private rendering API was used.

| Resource | Native rendition | SHA-256 | Bytes |
| --- | --- | --- | ---: |
| `AppDockLogoColor.png` | `Default` | `12212d08127905b6d5e0ad457b893ac27c75d194112cb0b2e3f961bc136528fe` | 436353 |
| `AppDockLogoClearLight.png` | `ClearLight` | `71c819e14b7ad5b4e394638f5010deed8edcd7985fb6113bf619a072c3695f36` | 344310 |
| `AppDockLogoClearDark.png` | `ClearDark` | `301dccfc3f19b7c9eaf9ebd43aee8a7d2e6ef468f25b9762e5f79db91004d2e5` | 377871 |

The files are 16-bit RGBA PNGs with transparent outer corners. The Clear
renditions contain the native exporter's opaque neutral backdrop: they are
static Mono artwork, not live transparency, refraction, or wallpaper sampling.
They are separate from the unchanged 128 × 128 in-app preview resources.

Dock choices take effect after restarting Wattson; the default keeps the Dock
icon hidden. These images do not modify the Finder/Applications icon, bundle
icon keys, or compiled native icon. Release, developer-install, and isolated
preview builds copy them into `Contents/Resources` before signing. Builds need
no export tool or private `dist` files.

To reproduce from the repository root, choose the rendition and output name
from the table:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  design/icon/WattsonGlass.icon --export-image \
  --output-file design/icon/dock-logo/AppDockLogoColor.png \
  --platform macOS --rendition Default --width 512 --height 512 --scale 1
```

The canonical icon source and all in-app preview bytes were unchanged by this
export; their source hashes remain recorded in `../in-app-logo/README.md`.
