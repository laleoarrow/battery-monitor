# In-app logo resources

These three checked-in 128 × 128 PNGs are direct macOS exports of the canonical
`../WattsonGlass.icon` document, made on 2026-09-13 with Apple's Icon Composer
`ictool` 1.6 (99.1), supplied by Xcode 26.6 (17F113). They provide the application’s
Color and Mono logo choices. Release, developer-install, and isolated-preview
builds copy these files into `Contents/Resources` before signing; building
requires no export tool.

| Resource | Native rendition | SHA-256 | Bytes |
| --- | --- | --- | ---: |
| `AppLogoColor.png` | `Default` | `bc045f86fb359bb39bee6d477d071229525b5074eecab38342a6daf980c40530` | 50839 |
| `AppLogoClearLight.png` | `ClearLight` | `2955b163811776229acd23faeaf5086feaac753983ec42e99ac22aafbff83057` | 37323 |
| `AppLogoClearDark.png` | `ClearDark` | `d3049461df88a18d3b7b1e88599fb9474c5b9341d25280b4121426199178d475` | 42810 |

All three files contain alpha and have transparent outer corners. The Clear
exports include an opaque neutral backdrop baked by the native exporter.
They are static Mono renderings: displaying them in an `NSImageView` does not
provide live transparency, refraction, wallpaper sampling, or dynamic lighting.
The source geometry and material settings were preserved without raster edits,
AI generation, or private rendering APIs. All three exports were visually
checked for the complete energy curve; tiny particles are decorative and their
individual legibility at small displayed sizes is not guaranteed.

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
| `icon.json` | `e2ded3dbf98d2da0597af36445e5a5125c16de822bf6a013744d108a31647c26` |
| `Assets/01-track.svg` | `7657699b2e04c367a3ab1c844814c8bf0d6d2f939a85205345dfd3853d8e7aae` |
| `Assets/02-energy.svg` | `347dba71fd73ec1a7b886a7f48e8d3ea5a263cf0f558a4a6543ec2033bbb7ce4` |
| `Assets/03-particles.svg` | `ab83e5aa878a0e1f84335037ddcbbe1b2f79df1c8522412bc2d8b17cf2be6cbd` |
