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
      assert.equal(await page.locator('#wattson-scroll-design').getAttribute('data-style'), 'hidden', 'The default must be hidden');
      assert.equal(await page.locator('#scrollbar-choice').inputValue(), 'hidden');
      assert.equal(await page.locator('#wattson-preview-rail').isVisible(), false);
      const metrics = await page.evaluate(() => ({
        width: innerWidth, documentWidth: document.documentElement.scrollWidth,
        documentHeight: document.documentElement.scrollHeight,
      }));
      assert.ok(metrics.documentWidth <= width + 1, `Horizontal overflow: ${JSON.stringify(metrics)}`);
      for (const style of ['hidden', 'simple', 'flow']) {
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
      await choose('flow');
      assert.ok(Math.abs((await scrollState()).top - beforeSwitch.top) <= 1, 'Changing style must preserve the reading position');
      const appearance = await page.evaluate(() => {
        const simple = getComputedStyle(document.querySelector('.ws-simple'));
        const flow = getComputedStyle(document.querySelector('.ws-flow'));
        const rail = document.querySelector('#wattson-preview-rail').getBoundingClientRect();
        const viewport = document.querySelector('#wattson-preview-scroll').getBoundingClientRect();
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 1;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = simple.backgroundColor;
        ctx.fillRect(0, 0, 1, 1);
        return {
          simpleWidth: simple.width, flowWidth: flow.width,
          simpleBackground: simple.backgroundImage, simpleRGBA: [...ctx.getImageData(0, 0, 1, 1).data],
          flowBackground: flow.backgroundImage,
          flowOverflow: flow.overflow, flowRadius: flow.borderRadius,
          flowBoxShadow: flow.boxShadow, flowFilter: flow.filter,
          railWidth: rail.width, railLeft: rail.left, viewportCenter: viewport.left + viewport.width / 2,
        };
      });
      assert.equal(appearance.simpleWidth, '6px');
      assert.equal(appearance.flowWidth, '6px', 'Flow stays inside the thin scrollbar');
      assert.equal(appearance.railWidth, 26, 'Keep the larger drag hit area');
      assert.ok(appearance.railLeft > appearance.viewportCenter, 'Scrollbar must stay on the right');
      assert.equal(appearance.simpleBackground, 'none', 'Simple remains a plain grey scrollbar');
      assert.ok(Math.max(...appearance.simpleRGBA.slice(0, 3)) - Math.min(...appearance.simpleRGBA.slice(0, 3)) <= 12, 'Simple must remain neutral grey');
      assert.ok(appearance.flowBackground.startsWith('linear-gradient('), 'Flow must have the theme gradient');
      assert.equal(appearance.flowOverflow, 'hidden', 'Flow light must be clipped inside its capsule');
      assert.ok(parseFloat(appearance.flowRadius) > 0, 'Flow capsule must have rounded ends');
      assert.equal(appearance.flowBoxShadow, 'none', 'No outside flow shadow');
      assert.ok(!/drop-shadow|blur/.test(appearance.flowFilter), 'No exterior flow glow filter');
      await scrollTo(0);
      let file = null;
      if (width === 736 || colorScheme === 'dark') {
        file = `scrollbar-flow-${width}-${colorScheme}.png`;
        await page.locator('#wattson-scroll-design').screenshot({path: path.join(output, file)});
      }
      let simpleFile = null;
      if (width === 736) {
        await choose('simple');
        simpleFile = `scrollbar-simple-${width}-${colorScheme}.png`;
        await page.locator('#wattson-scroll-design').screenshot({path: path.join(output, simpleFile)});
        await choose('flow');
      }
      evidence.layouts.push({...metrics, colorScheme, file, simpleFile, appearance, defaultHidden: true, noHorizontalOverflow: true, switchingPreservesPosition: true});
    }
  }
  const snapshot = () => page.locator('.ws-star').evaluateAll(nodes => nodes.map(node => ({
    transform: getComputedStyle(node).transform,
    opacity: getComputedStyle(node).opacity,
    x: node.getBoundingClientRect().x, y: node.getBoundingClientRect().y,
  })));
  await choose('flow');
  evidence.flowMotion = await page.evaluate(async () => {
    let samples = 0, outside = 0, downwardSteps = 0, invisibleResets = 0, visibleUpwardSteps = 0, nonuniformSpacingFrames = 0;
    let previous = null;
    const started = performance.now(), until = started + 5200;
    while (performance.now() < until) {
      await new Promise(resolve => requestAnimationFrame(resolve));
      const capsule = document.querySelector('.ws-flow').getBoundingClientRect();
      const current = [...document.querySelectorAll('.ws-star')].map(star => {
        const rect = star.getBoundingClientRect();
        return {x: rect.x, y: rect.y, right: rect.right, bottom: rect.bottom, opacity: Number(getComputedStyle(star).opacity)};
      });
      if (current.length !== 5) throw new Error('Flow requires exactly five independent points');
      for (const [index, rect] of current.entries()) {
        samples++;
        if (rect.opacity > 0.01 && (rect.x < capsule.left - 0.1 || rect.right > capsule.right + 0.1 ||
            rect.y < capsule.top - 0.1 || rect.bottom > capsule.bottom + 0.1)) outside++;
        if (previous) {
          const delta = rect.y - previous[index].y;
          if (delta > 0.01) downwardSteps++;
          if (delta < -0.01) {
            if (rect.opacity <= 0.01 || previous[index].opacity <= 0.01) invisibleResets++;
            else visibleUpwardSteps++;
          }
        }
      }
      const visibleYs = current.filter(p => p.opacity > 0.1).map(p => p.y).sort((a, b) => a - b);
      const gaps = visibleYs.slice(1).map((value, index) => value - visibleYs[index]);
      if (gaps.length >= 2 && Math.max(...gaps) - Math.min(...gaps) > 1) nonuniformSpacingFrames++;
      previous = current;
    }
    return {sampledMilliseconds: performance.now() - started, samples, pointCount: 5, outsideCapsule: outside,
      downwardSteps, invisibleResets, visibleUpwardSteps, nonuniformSpacingFrames};
  });
  assert.equal(evidence.flowMotion.outsideCapsule, 0, 'Visible points must remain inside the scrollbar');
  assert.ok(evidence.flowMotion.downwardSteps > 0, 'Light points must flow downward');
  assert.ok(evidence.flowMotion.invisibleResets > 0, 'Observe a hidden reset from bottom to top');
  assert.equal(evidence.flowMotion.visibleUpwardSteps, 0, 'No visible return journey upward');
  assert.ok(evidence.flowMotion.nonuniformSpacingFrames > 0, 'Point spacing must be nonuniform');
  const movingA = await snapshot();
  await page.waitForTimeout(250);
  const movingB = await snapshot();
  assert.ok(movingA.some((node, i) => Math.abs(node.y - movingB[i].y) > 0.1), 'Flow must actually move when motion is allowed');
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
