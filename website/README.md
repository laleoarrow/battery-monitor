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
links from the checked-in fallback version. The Pages workflow deploys only a
current `main` commit with successful same-SHA Headless CI and a `VERSION` that
matches the supplied stable release tag.
