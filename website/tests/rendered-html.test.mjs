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

async function configuredReleaseVersion() {
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  const fallback = page.match(/const PUBLIC_FALLBACK_VERSION = "(v\d+\.\d+\.\d+)";/);
  assert.ok(fallback, "website source must declare a public fallback version");
  assert.match(page, /process\.env\.NEXT_PUBLIC_RELEASE_VERSION/);
  const version = process.env.NEXT_PUBLIC_RELEASE_VERSION || fallback[1];
  assert.match(version, /^v\d+\.\d+\.\d+$/);
  return version;
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
  assert.match(html, /diagonal adapter plug/i);
  assert.match(html, /green bracketed charging battery/i);
  assert.match(html, /approved A1 power-flow icon direction/i);
  assert.match(html, /slightly smaller[\s\S]*and lighter/i);
  assert.match(html, /21-point Regular symbols/i);
  assert.match(html, /1.6-point custom outlines/i);
  assert.match(html, /real visible extents target 19.25–21.5 points/i);
  assert.match(html, /measure 20–21.25 points/i);
  assert.match(html, /simplified matching System chip/i);
  assert.match(html, /dedicated Menu Bar Icon page/i);
  assert.match(html, /Wattson icon only/i);
  assert.match(html, /Wattson with percentage/i);
  assert.match(html, /macOS 26 icon only/i);
  assert.match(html, /macOS 26 with percentage/i);
  assert.match(html, /appearances vertically/i);
  assert.match(html, /one full-width option per row/i);
  assert.match(html, /seven real production-rendered states/i);
  assert.match(
    html,
    /Battery, Full, Charging, Low, Low \+ AC, Saver, and Saver \+ AC/i,
  );
  assert.match(html, /full-size macOS 26 Control Center battery parts from the running system/i);
  assert.match(html, /23×12 outline and 11×14 bolt/i);
  assert.match(html, /Every connected state uses the system bolt/i);
  assert.match(html, /only the battery fill is yellow/i);
  assert.match(html, /outline, cap, and bolt keep the menu-bar foreground colour/i);
  assert.match(html, /real BatteryIcon renderer/i);
  assert.match(
    html,
    /percentage rows show matching per-state values to the left of each glyph/i,
  );
  assert.match(html, /General adds Check for Updates and Check for Updates on Launch/i);
  assert.match(html, /Manual checks read GitHub Latest Release/i);
  assert.match(html, /launch checks default on, stay quiet when current or offline/i);
  assert.match(html, /never download or install automatically/i);
  assert.match(html, /Optional update checks contact only GitHub Releases/i);
  assert.match(html, /Settings sidebar uses the real packaged Wattson app icon/i);
  assert.match(html, /720×520/i);
  const expectedVersion = await configuredReleaseVersion();
  assert.match(html, new RegExp(expectedVersion.replaceAll(".", "\\."), "i"));
  assert.match(html, /bundled stable release/i);
  assert.match(html, /not Apple-notarized/i);
  assert.match(html, /System Settings[\s\S]*Privacy[\s\S]*Security[\s\S]*Open Anyway/i);
  assert.doesNotMatch(html, /Control-click/i);
  assert.doesNotMatch(
    html,
    /Installers converge|canonical copy passes validation|graphical-install rollback/i,
  );
  assert.doesNotMatch(html, /percentage (?:control )?(?:remains|stays) in General/i);
  assert.doesNotMatch(html, /all four complete appearances in one row/i);
  assert.doesNotMatch(html, /Your site is taking shape|Starter Project/i);
});

test("groups the install routes in one compact, accessible panel", async () => {
  const response = await render();
  const html = await response.text();
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(html, /class="install-panel"/i);
  assert.equal(
    (html.match(/<article class="install-row\b/gi) ?? []).length,
    3,
  );
  assert.match(
    html,
    /class="install-row install-row-recommended"[\s\S]*?Recommended[\s\S]*?Download DMG/i,
  );
  assert.match(
    html,
    /class="install-row"[\s\S]*?Package installer[\s\S]*?Download PKG/i,
  );
  assert.match(
    html,
    /class="install-row install-row-homebrew"[\s\S]*?brew install --cask laleoarrow\/tap\/wattson[\s\S]*?aria-label="Copy Homebrew install command"/i,
  );
  assert.match(html, /class="trust-note"[\s\S]*?Inspect releases/i);
  assert.doesNotMatch(html, /class="install-grid"|class="install-card\b/i);

  assert.match(page, /className="install-shell"/);
  assert.match(
    css,
    /\.install-shell\s*\{[^}]*width:\s*min\(760px,\s*calc\(100% - 48px\)\)/s,
  );
  assert.match(css, /\.install-panel\s*\{[^}]*border-radius:\s*14px/s);
  assert.match(css, /\.install-row\s*\{[^}]*grid-template-columns:/s);
  assert.match(css, /\.install-action\s*\{[^}]*min-height:\s*40px/s);
  assert.doesNotMatch(css, /\.install-card\b/);
  assert.doesNotMatch(
    css,
    /\.install-section\s*\{[^}]*padding:\s*145px\s+0\s+100px/s,
  );
  assert.doesNotMatch(
    css,
    /\.install-row\s*\{[^}]*min-height:\s*(?:3[4-9]\d|[4-9]\d\d)px/s,
  );
});

test("shows the current AppKit popover instead of an invented web mock", async () => {
  const response = await render();
  const html = await response.text();
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");

  assert.match(
    html,
    /wattson-popover-real\.png[^>]*alt="The real Wattson menu bar popover/i,
  );
  assert.match(html, /Captured from Wattson’s production AppKit hierarchy\./i);
  assert.doesNotMatch(html, /class="app-window"|class="power-map"/i);
  assert.doesNotMatch(page, /historyValues|className="app-window"|67\.1 W|24\.8 W/);

  await Promise.all([
    access(new URL("../public/wattson-popover-real.png", import.meta.url)),
    access(new URL("../dist/client/wattson-popover-real.png", import.meta.url)),
  ]);
});

test("ships the required static assets", async () => {
  await Promise.all([
    access(new URL("../dist/client/favicon.png", import.meta.url)),
    access(new URL("../dist/client/og.png", import.meta.url)),
    access(new URL("../dist/client/wattson-popover-real.png", import.meta.url)),
    access(new URL("../dist/client/_next/", import.meta.url)),
  ]);

  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  assert.match(page, /api\.github\.com\/repos\/laleoarrow\/battery-monitor\/releases\/latest/);
  assert.match(page, /Apple silicon \+ Intel/);
  assert.match(page, /macOS 12\+/);
});

test("exports a server-independent GitHub Pages document", async () => {
  const html = await readFile(new URL("../../docs/index.html", import.meta.url), "utf8");
  const configuredVersion = await configuredReleaseVersion();
  const version = configuredVersion.slice(1);
  const assets = await readdir(new URL("../../docs/_next/", import.meta.url), {
    recursive: true,
  });
  const assetBase = `https://github.com/laleoarrow/battery-monitor/releases/download/v${version}`;

  assert.match(html, /<title>Wattson — Live power flow for macOS<\/title>/i);
  assert.match(html, /href="\/battery-monitor\/_next\/static\/css\//i);
  assert.match(html, /src="\/battery-monitor\/wattson-popover-real\.png"/i);
  assert.doesNotMatch(html, /_next\/image\?url=%2Fwattson-popover-real\.png/i);
  await access(new URL("../../docs/wattson-popover-real.png", import.meta.url));
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

test("lets release workflows read VERSION when the optional input is blank", async () => {
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
    assert.match(versionInput[1], /^\s+required:\s*false\s*$/m);
    assert.match(versionInput[1], /leave blank/i);
    assert.doesNotMatch(versionInput[1], /^\s+default:/m);
    assert.match(workflow, /if \[\[ -z "\$WATTSON_VERSION" \]\]; then/);
    assert.match(workflow, /< VERSION/);
  }
});
