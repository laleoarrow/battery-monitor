# Settings logo verification

Verified 14 October 2026 against the production Swift sources at `689a232`.

The [original VM capture](../settings-five-modules.png) showed the system
blueprint placeholder because its QA builder created `Contents/MacOS` but
omitted `Contents/Resources`. With both the chosen `AppLogo` image and
`AppIconSettings` absent, `SettingsLogoArtwork` used the bundle's system icon.
The QA packaging has been corrected to include the real artwork. The release
builder already includes these resources; all three installed logo PNGs match
the repository byte for byte, and the installed 4.3.1 signature verifies.

An isolated bundle compiled the unchanged production views. The missing-resource
control and corrected bundle each exercised Classic/Glass, light/dark, and
Color/Clear: 16 cases and 144 resource, layout, and lifecycle checks passed.
Without resources, the sidebar image's decoded TIFF exactly matched the system
fallback. With resources, it exactly matched the selected production PNG.

The following are actual AppKit `cacheDisplay` renders of the hidden Settings
window, not WindowServer screenshots. All four Classic images were visually
checked: the logo and all five module rows render completely. Glass resource
selection and layout checks passed, but its offscreen images lack system
compositor content and are excluded from visual evidence. No new claim about
WindowServer glass rendering is made by this check.

| Artwork | Light | Dark |
| --- | --- | --- |
| Color | [Render](settings-classic-light-color.png) | [Render](settings-classic-dark-color.png) |
| Clear | [Render](settings-classic-light-clear.png) | [Render](settings-classic-dark-clear.png) |

[Missing-resource control](missing-resources.png) reproduces the placeholder.
[Evidence](evidence.json) retains production-source, resource, executable and
image hashes, per-case checks, packaging provenance and cleanup results.
The harness and archived QA apps remain in the project-local scratch directory
recorded in that evidence.

The 15 focused runtime tests and 22 release-packaging tests also passed.
No production code or installed app was changed. The test windows stayed hidden,
the foreground app did not change, and both QA bundles were unregistered and
removed after archiving. Their process, Spotlight and LaunchServices checks
found no remaining instances. The test VMs stayed stopped during this check.
