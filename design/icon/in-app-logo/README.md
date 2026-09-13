# In-app logo resources

These three checked-in 128 × 128 PNGs are direct macOS exports of the canonical
`../WattsonGlass.icon` document, made on 2026-09-13 with Apple's Icon Composer
`ictool` 1.6 (99.1), supplied by Xcode 26.6 (17F113). They provide the application’s
Color and Mono logo choices. Release, developer-install, and isolated-preview
builds copy these files into `Contents/Resources` before signing; building
requires no export tool.

| Resource | Native rendition | SHA-256 | Bytes |
| --- | --- | --- | ---: |
| `AppLogoColor.png` | `Default` | `b5d4134fe0c4254279de1953a17214ed69d0473bb1e49093a597ea82e10219f8` | 50842 |
| `AppLogoClearLight.png` | `ClearLight` | `e9882dfaab15ce5eff5ebaaa28821b2d6f12600f03c1986b469281127db02b2a` | 38158 |
| `AppLogoClearDark.png` | `ClearDark` | `4fa6f526276c87bb7b4f9d8c8ea2fdc4f9ddaf2e7609c06c5526dae2328b57a0` | 43183 |

All three files contain alpha and have transparent outer corners. The Clear
exports include an opaque neutral backdrop baked by the native exporter.
They are static Mono renderings: displaying them in an `NSImageView` does not
provide live transparency, refraction, wallpaper sampling, or dynamic lighting.
The 4.2 source retains the energy curve and four light positions while slightly
enlarging their cores and reducing the native Mono/tinted energy fill to 75%
white alpha. Composer supplies the specular edges; no raster edits, baked blur,
AI generation, or private rendering APIs are used. Native exports were inspected
at 32, 64, 128 and 512 pixels in Default, Dark, Clear and Tinted appearances.
The Clear light cores separate more clearly from the white band at larger sizes.
They are still decorative: individual tiny particles are not resolved at every
small displayed size, and these flat exports are not a live-backdrop validation.

This application preference does not choose or modify the Finder/Dock icon.
The primary `WattsonGlass` bundle icon keys and the compiled layered system icon
remain separate from these named image resources.

To reproduce a resource from the repository root, choose the exact rendition
and corresponding output filename from the table:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  design/icon/WattsonGlass.icon --export-image \
  --output-file design/icon/in-app-logo/AppLogoColor.png \
  --platform macOS --rendition Default --width 128 --height 128 --scale 1
```

The canonical source files were unchanged before and after this export:

| Source file within `WattsonGlass.icon` | SHA-256 |
| --- | --- |
| `icon.json` | `fe4f500e155f111017082dbfe2c19a79ae6e92b5742fbe02f68ee59947fc85d4` |
| `Assets/01-track.svg` | `7657699b2e04c367a3ab1c844814c8bf0d6d2f939a85205345dfd3853d8e7aae` |
| `Assets/02-energy.svg` | `347dba71fd73ec1a7b886a7f48e8d3ea5a263cf0f558a4a6543ec2033bbb7ce4` |
| `Assets/03-particles.svg` | `a725df752bcae23d494eae8b2ac2db85ff0a617f48b07ccd3ed6fcb727a48c04` |
