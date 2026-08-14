import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("https://laleoarrow.github.io/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders the complete English Wattson release page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html lang="en">/i);
  assert.match(html, /See where[\s\S]*every watt[\s\S]*goes\./i);
  assert.match(html, /Download DMG/i);
  assert.match(html, /Download PKG/i);
  assert.match(html, /brew install --cask laleoarrow\/tap\/wattson/i);
  assert.match(html, /Community build/i);
  assert.match(html, /macOS-style battery glyph/i);
  assert.match(html, /refined 2A airy-glass selector/i);
  assert.match(html, /stays at 1× while dragging/i);
  assert.match(html, /system Reduce Motion/i);
  assert.match(html, /native 2C segmented control/i);
  assert.match(html, /without an app setting or saved preference/i);
  assert.match(html, /not Apple-notarized/i);
  assert.match(html, /System Settings[\s\S]*Privacy[\s\S]*Security[\s\S]*Open Anyway/i);
  assert.doesNotMatch(html, /Control-click/i);
  assert.doesNotMatch(html, /Your site is taking shape|Starter Project/i);
});

test("ships the required static assets", async () => {
  await Promise.all([
    access(new URL("../dist/client/favicon.png", import.meta.url)),
    access(new URL("../dist/client/og.png", import.meta.url)),
    access(new URL("../dist/client/_next/", import.meta.url)),
  ]);

  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  assert.match(page, /api\.github\.com\/repos\/laleoarrow\/battery-monitor\/releases\/latest/);
  assert.match(page, /Apple silicon \+ Intel/);
  assert.match(page, /macOS 12\+/);
});

test("exports a server-independent GitHub Pages document", async () => {
  const html = await readFile(new URL("../../docs/index.html", import.meta.url), "utf8");
  const version = (
    await readFile(new URL("../../VERSION", import.meta.url), "utf8")
  ).trim();
  const assets = await readdir(new URL("../../docs/_next/", import.meta.url), {
    recursive: true,
  });
  const assetBase = `https://github.com/laleoarrow/battery-monitor/releases/download/v${version}`;

  assert.match(html, /<title>Wattson — Live power flow for macOS<\/title>/i);
  assert.match(html, /href="\/battery-monitor\/_next\/static\/css\//i);
  assert.ok(
    html.includes(
      `href="${assetBase}/Wattson-v${version}-macos-universal.dmg"`,
    ),
  );
  assert.ok(
    html.includes(
      `href="${assetBase}/Wattson-v${version}-macos-universal.pkg"`,
    ),
  );
  assert.doesNotMatch(html, /<script\b/i);
  assert.doesNotMatch(html, /rel="modulepreload"/i);
  assert.doesNotMatch(html, /vinext\.navigationRuntime|"initialCacheKind":"dynamic"/i);
  assert.doesNotMatch(html, /class="copy-button"/i);
  assert.equal(assets.some((asset) => asset.endsWith(".js")), false);
});

test("preserves non-site documentation during the Pages export", async () => {
  const exporter = await readFile(
    new URL("../scripts/export-pages.mjs", import.meta.url),
    "utf8",
  );

  assert.doesNotMatch(
    exporter,
    /rm\(outputRoot,\s*\{[^}]*recursive:\s*true[^}]*\}\)/s,
  );
  await Promise.all([
    access(
      new URL(
        "../../docs/superpowers/plans/2026-08-13-settings-window.md",
        import.meta.url,
      ),
    ),
    access(
      new URL(
        "../../docs/superpowers/specs/2026-08-13-settings-window-design.md",
        import.meta.url,
      ),
    ),
    access(
      new URL(
        "../../docs/superpowers/specs/assets/wattson-settings-c-plus-e.png",
        import.meta.url,
      ),
    ),
  ]);
});

test("keeps release workflow defaults aligned with VERSION", async () => {
  const version = (
    await readFile(new URL("../../VERSION", import.meta.url), "utf8")
  ).trim();
  const workflowUrls = [
    new URL("../../.github/workflows/promote-release.yml", import.meta.url),
    new URL("../../.github/workflows/macos-helper-install.yml", import.meta.url),
  ];

  for (const workflowUrl of workflowUrls) {
    const workflow = await readFile(workflowUrl, "utf8");
    const versionInput = workflow.match(
      /^\s+version:\s*\n((?:^\s{8,}.*\n){1,8})/m,
    );
    assert.ok(versionInput, `${workflowUrl.pathname} is missing the version input`);
    const defaultVersion = versionInput[1].match(
      /^\s+default:\s*["']?([^"'\s]+)["']?\s*$/m,
    );
    assert.equal(defaultVersion?.[1], version, workflowUrl.pathname);
  }
});
