import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const gallery = path.dirname(fileURLToPath(import.meta.url));
const [packageDirectory, scratch, mode] = process.argv.slice(2);
const {chromium} = await import(pathToFileURL(path.join(packageDirectory, 'index.mjs')).href);
const evidenceDirectory = path.resolve(gallery, '../../release-v5.0.3/gallery-validation');
await fs.mkdir(evidenceDirectory, {recursive: true});
const evidence = {version: '5.0.3', method: 'Isolated browser design render; no running-App screenshots or network requests', svgRenders: [], scrollbarRenders: [], layouts: [], errors: [], browserClosed: false};
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
evidence.indexSHA256 = hash(await fs.readFile(path.join(gallery, 'index.html')));
if (mode !== '--svg-only') evidence.gifSHA256 = hash(await fs.readFile(path.join(gallery, 'previews/full-charge-orbit.gif')));
let succeeded = false;
const context = await chromium.launchPersistentContext(path.join(scratch, 'profile'), {
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  viewport: {width: 1200, height: 1040},
  deviceScaleFactor: 1,
  ignoreDefaultArgs: ['--enable-features=CDPScreenshotNewSurface'],
  args: ['--disable-gpu', '--disable-background-networking', '--disable-component-update', '--no-first-run'],
});
evidence.browser = context.browser()?.version() ?? 'Chromium';
try {
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.origin !== 'https://gallery.wattson.test') return route.abort();
    const relative = decodeURIComponent(url.pathname).slice(1) || 'index.html';
    const target = path.resolve(gallery, relative);
    if (!target.startsWith(gallery + path.sep)) return route.abort();
    try {
      const contentType = ({'.html': 'text/html', '.png': 'image/png', '.gif': 'image/gif', '.svg': 'image/svg+xml'})[path.extname(target)] ?? 'application/octet-stream';
      await route.fulfill({status: 200, contentType, body: await fs.readFile(target)});
    } catch { await route.abort(); }
  });
  const page = await context.newPage();
  page.on('pageerror', error => evidence.errors.push(String(error)));
  for (const theme of ['light', 'dark']) {
    const relative = `previews/time-source-${theme}.svg`;
    const bytes = await fs.readFile(path.join(gallery, relative));
    await page.emulateMedia({colorScheme: theme});
    await page.goto(`https://gallery.wattson.test/${relative}`);
    await page.evaluate(() => document.fonts.ready);
    const target = path.join(gallery, 'previews', `time-source-${theme}.png`);
    await page.screenshot({path: target});
    evidence.svgRenders.push({source: relative, sourceSHA256: hash(bytes), pngSHA256: hash(await fs.readFile(target)), width: 1200, height: 1040});
  }
  await page.setViewportSize({width: 736, height: 700});
  for (const theme of ['light', 'dark']) {
    await page.emulateMedia({colorScheme: theme, reducedMotion: 'no-preference'});
    await page.goto('https://gallery.wattson.test/scrollbar-preview.html');
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await page.locator('#wattson-scroll-design').getAttribute('data-style'), 'flow');
    assert.equal(await page.locator('#scrollbar-choice').inputValue(), 'flow');
    assert.equal(await page.locator('.ws-caption').textContent(), '默认：流光');
    const target = path.join(gallery, 'previews', `scrollbar-flow-${theme}.png`);
    await page.locator('#wattson-scroll-design').screenshot({path: target});
    evidence.scrollbarRenders.push({theme, defaultStyle: 'flow', pngSHA256: hash(await fs.readFile(target))});
  }
  if (mode !== '--svg-only') {
    for (const width of [1200, 390]) {
      for (const theme of ['light', 'dark']) {
        await page.setViewportSize({width, height: 900});
        await page.emulateMedia({colorScheme: theme, reducedMotion: 'reduce'});
        await page.goto('https://gallery.wattson.test/');
        await page.locator('img').evaluateAll(images => images.forEach(image => { image.loading = 'eager'; }));
        await page.waitForFunction(() => [...document.images].every(image => image.complete && image.naturalWidth > 0));
        const state = await page.evaluate(() => ({
          viewportWidth: innerWidth,
          documentWidth: document.documentElement.scrollWidth,
          imageCount: document.images.length,
          posterSelected: document.querySelector('#full picture img').currentSrc.endsWith('/full-charge-orbit-poster.png'),
          heading: document.querySelector('h1').textContent,
        }));
        assert.ok(state.documentWidth <= width + 1, `Horizontal overflow: ${JSON.stringify(state)}`);
        assert.ok(state.posterSelected, 'Reduce Motion must select the static poster');
        const file = `gallery-${width}-${theme}.png`;
        await page.screenshot({path: path.join(evidenceDirectory, file), fullPage: true});
        await page.emulateMedia({reducedMotion: 'no-preference'});
        await page.waitForFunction(() => {
          const image = document.querySelector('#full picture img');
          return image.complete && image.naturalWidth > 0 && image.currentSrc.endsWith('/full-charge-orbit.gif');
        });
        evidence.layouts.push({width, theme, file, ...state, gifSelectedWithMotion: true});
      }
    }
    assert.deepEqual(evidence.errors, []);
  }
  succeeded = true;
} finally {
  await context.close();
  evidence.browserClosed = true;
  evidence.allPassed = succeeded && evidence.errors.length === 0 && (mode === '--svg-only' || evidence.layouts.length === 4);
  await fs.writeFile(path.join(evidenceDirectory, mode === '--svg-only' ? 'svg-render.json' : 'verification.json'), JSON.stringify(evidence, null, 2) + '\n');
}
console.log(JSON.stringify({svgRenders: evidence.svgRenders.length, layouts: evidence.layouts.length, errors: evidence.errors.length, browserClosed: evidence.browserClosed}));
