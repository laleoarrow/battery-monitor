# Wattson 5.0.2 release communication

The reviewed HTML card and matching text were sent to Cody after the public
release, website and canonical installation gates passed. `sent-receipt.json`
records the verified Sent message and exact body hashes. Private recipient
addresses are not stored here.

- `subject.txt`: Chinese release-email subject.
- `email.html`: presentation-table email card with inline base styles, readable
  light/dark colors, an optional dark-mode media query and descriptive alt text.
- `email.txt`: matching plain-text alternative.
- `release-notes.md`: concise Chinese release notes with an English summary.

The content follows `.agent/release.md` and the 5.0.1 release notes/gallery
structure. No local 5.0.1 HTML email source was present. The email has no scripts,
remote fonts, external stylesheets, tracking pixels or runtime screenshots.

## Completed publication checks

1. The two design-preview URLs are
   `previews/time-source-light.png` and `previews/time-source-dark.png` under the
   versioned gallery URL. They show the source indicators and gradient clock.
   Captions identify them as design previews, not runtime screenshots. Anonymous
   public downloads matched the frozen artwork before sending.
2. Release, PKG, DMG, checksum and gallery links use the repository's established
   versioned URL structure. All were verified after the release and Pages gates
   passed; see `../publication/public-site-verification.json` and the separate
   anonymous installer provenance record.
3. The published artifacts retain `community-ad-hoc` metadata, matching the
   email's signing and notarization description.
4. The sending agent confirmed the recipients from prior correspondence,
   found no Sent duplicate for 5.0.2, sent both alternatives, then read back the
   Sent label, recipients, subject and exact MIME bodies. Only download links
   were sent, without installer attachments. The retained HTML is exactly the
   sent body, including its invisible preflight comment.

All time readings are described as dynamic estimates. The PKG/helper versus
app-only DMG distinction is retained.

## Browser previews

`render-preview.sh EXISTING_PLAYWRIGHT_PACKAGE_DIRECTORY` reuses an installed
Playwright package and the installed Chrome executable; it installs nothing.
It owns a unique project-local `.noindex` scratch folder and browser profile,
and uses the project's process/lifecycle helpers to clean them on exit.

The renderer writes four final **mail design preview** PNGs under `previews/`:
desktop at a 1000-pixel viewport and narrow at 390 pixels, each in Light/Dark.
`previews/verification.json` records source and artwork hashes, dimensions,
horizontal-overflow checks and the browser's completed close operation.

For this prepublication check, the two public image URLs are fulfilled from
the corresponding local design PNGs. All other page requests are blocked.
This verifies the HTML layout and its artwork together without claiming that
the public links are already live. It is not a screenshot of Apple Mail,
Gmail or Outlook. Those clients may sanitize CSS, block remote images or apply
their own dark-mode color inversion; their exact rendering remains unverified.

The 2026-10-27 local preview run completed all four cases in Chrome 155.0.8059.85
through Playwright 1.58.2. Desktop exports are 1000 × 2277 pixels; narrow exports
are 390 × 2111 pixels. All four were visually inspected: text and buttons remain
readable, the two design images load, and no horizontal overflow was detected.
After the owner exited, its scratch-folder and browser/renderer-process checks
both reported zero remaining resources. No user browser profile was used.
