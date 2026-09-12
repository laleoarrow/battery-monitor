# Wattson website

English product and download site for Wattson. It is built with vinext for
OpenAI Sites and can also emit a static GitHub Pages artifact.

## Verify

```bash
npm ci
npm test
npm run lint
npm run export:pages
```

`npm run export:pages` requires a completed `npm run build` and writes the
validated static site to the repository's `docs/` directory.

The interactive hosting build resolves the current stable release through
GitHub's public API. The GitHub Pages export is deliberately server-independent:
it removes the Vinext hydration runtime and uses direct universal DMG and PKG
links from `NEXT_PUBLIC_RELEASE_VERSION`, or the checked-in public fallback
when that build input is absent. The Pages workflow deploys only a
current `main` commit with successful same-SHA Headless CI and a `VERSION` that
matches the supplied stable release tag.

The installation panel distinguishes the app-only DMG (the universal
`Wattson.app` plus Applications shortcut) from the full App/helper PKG also used
by Homebrew. Keep the older-DMG warning: previously published images contain a
PKG, so they still require the full installation. Existing PKG users must update
through PKG or Homebrew to keep the app, helper, and receipt aligned. Source
changes must not imply that new packaging is already publicly downloadable.

Do not describe read-only monitoring as full SMC coverage or a Gatekeeper
bypass. Community App/helper signatures remain ad-hoc; the PKG/DMG are unsigned
and not notarized. The same release trust warning applies to both routes.
