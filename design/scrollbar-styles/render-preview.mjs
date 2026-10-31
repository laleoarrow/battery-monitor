import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const root = path.dirname(fileURLToPath(import.meta.url));
const [packageDirectory, scratch] = process.argv.slice(2);
const {chromium} = await import(pathToFileURL(path.join(packageDirectory, 'index.mjs')).href);
const packageInfo = JSON.parse(await fs.readFile(path.join(packageDirectory, 'package.json'), 'utf8'));
const fragment = await fs.readFile(path.join(root, 'scrollbar-style-preview.html'), 'utf8');
const output = path.join(root, 'previews');
await fs.mkdir(output, {recursive: true});
const evidence = {
  kind: 'Interactive scrollbar design preview; not a running native App screenshot',
  checkedAtUTC: new Date().toISOString(),
  sourceSHA256: createHash('sha256').update(fragment).digest('hex'),
  playwright: packageInfo.version,
  scratch,
  networkRequestsAllowed: false,
  layouts: [],
  interactions: [],
  errors: [],
  allPassed: false,
};
const context = await chromium.launchPersistentContext(path.join(scratch, 'profile'), {
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  viewport: {width: 736, height: 1000},
  deviceScaleFactor: 1,
  ignoreDefaultArgs: ['--enable-features=CDPScreenshotNewSurface'],
  args: ['--disable-gpu', '--disable-background-networking', '--disable-component-update', '--no-first-run'],
});
evidence.browser = context.browser()?.version() ?? 'Chromium';
await context.route('**/*', route => route.abort());
const page = await context.newPage();
page.on('pageerror', error => evidence.errors.push(String(error)));
const settle = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
const scrollState = () => page.locator('#wattson-preview-scroll').evaluate(node => ({
  top: node.scrollTop, max: node.scrollHeight - node.clientHeight, height: node.clientHeight,
}));
const scrollTo = async top => {
  await page.locator('#wattson-preview-scroll').evaluate((node, value) => { node.scrollTop = value; }, top);
  await settle();
};
const choose = async style => {
  await page.selectOption('#scrollbar-choice', style);
  await settle();
  assert.equal(await page.locator('#wattson-scroll-design').getAttribute('data-style'), style);
};

try {
  for (const width of [736, 320]) {
    for (const colorScheme of ['light', 'dark']) {
      await page.setViewportSize({width, height: 1000});
      await page.emulateMedia({colorScheme, reducedMotion: 'no-preference'});
      await page.goto('about:blank');
      await page.setContent('<!doctype html><html><head><meta charset="utf-8"><style>html{color-scheme:light dark}body{margin:0}</style></head><body>' + fragment + '</body></html>', {waitUntil: 'load'});
      await settle();
      await choose('orbit');
      const metrics = await page.evaluate(() => ({
        width: innerWidth, documentWidth: document.documentElement.scrollWidth,
        documentHeight: document.documentElement.scrollHeight,
      }));
      assert.ok(metrics.documentWidth <= width + 1, `Horizontal overflow: ${JSON.stringify(metrics)}`);
      for (const style of ['hidden', 'simple', 'orbit']) {
        await scrollTo(0);
        await choose(style);
        const original = await scrollState();
        assert.ok(original.max > 100, 'Small-screen preview must overflow vertically');
        const scrollBox = await page.locator('#wattson-preview-scroll').boundingBox();
        await page.mouse.move(scrollBox.x + scrollBox.width * 0.6, scrollBox.y + scrollBox.height * 0.5);
        await page.mouse.wheel(0, 180);
        await page.waitForFunction(() => document.querySelector('#wattson-preview-scroll').scrollTop > 10);
        await settle();
        const afterWheel = await scrollState();
        const railVisible = await page.locator('#wattson-preview-rail').isVisible();
        assert.equal(railVisible, style !== 'hidden', `${style} rail visibility`);
        if (style !== 'hidden') {
          const thumb = await page.locator('.ws-thumb').boundingBox();
          const rail = await page.locator('#wattson-preview-rail').boundingBox();
          assert.ok(thumb && rail && thumb.height < rail.height, 'Proportional draggable thumb required');
          await page.mouse.move(thumb.x + thumb.width / 2, thumb.y + thumb.height / 2);
          await page.mouse.down();
          await page.mouse.move(rail.x + rail.width / 2, rail.y + rail.height - 1, {steps: 12});
          await page.mouse.up();
          await settle();
          const afterDrag = await scrollState();
          assert.ok(afterDrag.max - afterDrag.top <= 2, `${style} drag must reach bottom: ${JSON.stringify(afterDrag)}`);
        }
        evidence.interactions.push({width, colorScheme, style, wheelMoved: afterWheel.top > 10, railVisible, dragBottomPassed: style === 'hidden' ? null : true});
      }
      await scrollTo(160);
      const beforeSwitch = await scrollState();
      await choose('simple');
      await choose('hidden');
      await choose('orbit');
      assert.ok(Math.abs((await scrollState()).top - beforeSwitch.top) <= 1, 'Changing style must preserve the reading position');
      await scrollTo(0);
      let file = null;
      if (width === 736 || colorScheme === 'dark') {
        file = `scrollbar-orbit-${width}-${colorScheme}.png`;
        await page.locator('#wattson-scroll-design').screenshot({path: path.join(output, file)});
      }
      evidence.layouts.push({...metrics, colorScheme, file, noHorizontalOverflow: true, switchingPreservesPosition: true});
    }
  }
  const snapshot = () => page.locator('.ws-star').evaluateAll(nodes => nodes.map(node => ({
    transform: getComputedStyle(node).transform,
    opacity: getComputedStyle(node).opacity,
    x: node.getBoundingClientRect().x, y: node.getBoundingClientRect().y,
  })));
  await choose('orbit');
  const movingA = await snapshot();
  await page.waitForTimeout(250);
  const movingB = await snapshot();
  assert.ok(movingA.some((node, i) => Math.abs(node.x - movingB[i].x) > 0.1 || Math.abs(node.y - movingB[i].y) > 0.1), 'Orbit must actually move when motion is allowed');
  evidence.orbitMotion = {starsChangePosition: true, sampledMilliseconds: 250};
  await page.emulateMedia({reducedMotion: 'reduce'});
  try {
    await page.waitForFunction(() => matchMedia('(prefers-reduced-motion: reduce)').matches &&
      document.querySelector('#wattson-scroll-design').dataset.reduceMotion === 'true', null, {timeout: 2000});
  } catch (error) {
    evidence.reducedMotionObservation = await page.evaluate(() => ({
      currentMediaMatches: matchMedia('(prefers-reduced-motion: reduce)').matches,
      declaredReducedMotion: document.querySelector('#wattson-scroll-design').dataset.reduceMotion,
    }));
    throw error;
  }
  const stillA = await snapshot();
  assert.ok(stillA.length > 0, 'Expected a stable star marker for motion verification');
  await page.waitForTimeout(250);
  const stillB = await snapshot();
  assert.deepEqual(stillA, stillB, 'Reduced-motion stars must remain static');
  evidence.reducedMotion = {media: 'reduce', starsStatic: true, sampledMilliseconds: 250};
  assert.equal(evidence.errors.length, 0, 'No browser execution errors');
  evidence.allPassed = true;
} catch (error) {
  evidence.failure = String(error.stack || error);
  throw error;
} finally {
  await context.close();
  evidence.browserContextClosed = true;
  await fs.writeFile(path.join(root, 'verification.json'), JSON.stringify(evidence, null, 2) + '\n');
}
console.log(`Scrollbar design checks passed: ${evidence.layouts.length} layouts, ${evidence.interactions.length} style interactions, reduced-motion static; isolated browser closed.`);
