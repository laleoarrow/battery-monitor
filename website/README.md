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

The page resolves the current stable release through GitHub's public API and
links directly to the universal DMG and PKG assets. Publish v3.0.0 before the
site so the API cannot surface an older Apple-silicon-only release.
