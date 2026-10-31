import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

const root = path.dirname(fileURLToPath(import.meta.url));
const [packageDirectory, scratch] = process.argv.slice(2);
const {chromium} = await import(pathToFileURL(path.join(packageDirectory, 'index.mjs')).href);
const packageInfo = JSON.parse(await fs.readFile(path.join(packageDirectory, 'package.json'), 'utf8'));
const html = await fs.readFile(path.join(root, 'email.html'), 'utf8');
const output = path.join(root, 'previews');
await fs.mkdir(output, {recursive: true});
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const art = new Map();
for (const name of ['full-charge-orbit.gif']) {
  const bytes = await fs.readFile(path.join(root, '../../releases/v5.0.3/previews', name));
  art.set(`https://laleoarrow.github.io/battery-monitor/design/v5.0.3/previews/${name}`, {name, bytes});
}
const context = await chromium.launchPersistentContext(path.join(scratch, 'profile'), {
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  viewport: {width: 1000, height: 900},
  deviceScaleFactor: 1,
  ignoreDefaultArgs: ['--enable-features=CDPScreenshotNewSurface'],
  args: ['--disable-gpu', '--disable-background-networking', '--disable-component-update', '--no-first-run'],
});
const evidence = {
  kind: 'Mail design preview — isolated Chromium browser rendering, not a mail-client screenshot',
  playwright: packageInfo.version,
  browser: context.browser()?.version() ?? 'Chromium',
  emailSHA256: hash(html),
  publicLinksVerified: false,
  previewImages: [...art.entries()].map(([url, {name, bytes}]) => ({url, localArtwork: name, sha256: hash(bytes)})),
  artworkMethod: 'Public image URLs fulfilled from the corresponding local approved-design GIF; no network requests sent.',
  cases: [],
  limitations: 'Not an Apple Mail, Gmail or Outlook render. Email-client sanitization, image blocking and automatic color inversion may differ. Public release and artwork URLs require separate anonymous verification after publication.',
};
try {
  await context.route('**/*', async route => {
    const image = art.get(route.request().url());
    if (image) await route.fulfill({status: 200, contentType: 'image/gif', body: image.bytes});
    else await route.abort();
  });
  const page = await context.newPage();
  for (const size of [{name: 'desktop', width: 1000, height: 900}, {name: 'narrow', width: 390, height: 844}]) {
    for (const colorScheme of ['light', 'dark']) {
      await page.setViewportSize({width: size.width, height: size.height});
      await page.emulateMedia({colorScheme});
      await page.setContent(html, {waitUntil: 'load'});
      await page.waitForFunction(() => [...document.images].every(image => image.complete && image.naturalWidth > 0));
      const metrics = await page.evaluate(() => ({
        viewportWidth: innerWidth,
        documentWidth: document.documentElement.scrollWidth,
        documentHeight: document.documentElement.scrollHeight,
        heading: document.querySelector('h1').innerText,
        images: [...document.images].map(image => ({alt: image.alt, width: image.width, height: image.height, naturalWidth: image.naturalWidth})),
        linkCount: document.links.length,
        background: getComputedStyle(document.body).backgroundColor,
        titleColor: getComputedStyle(document.querySelector('h1')).color,
      }));
      if (metrics.documentWidth > metrics.viewportWidth + 1) throw new Error(`Horizontal overflow: ${JSON.stringify(metrics)}`);
      const file = `mail-design-preview-${size.name}-${colorScheme}.png`;
      await page.screenshot({path: path.join(output, file), fullPage: true});
      evidence.cases.push({name: `${size.name}-${colorScheme}`, file, ...metrics});
    }
  }
} finally {
  await context.close();
  evidence.browserContextClosed = true;
  await fs.writeFile(path.join(output, 'verification.json'), JSON.stringify(evidence, null, 2) + '\n');
}
console.log(`Mail design previews: ${evidence.cases.length} layouts, no horizontal overflow; isolated browser closed.`);
