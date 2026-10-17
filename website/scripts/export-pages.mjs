import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";

const siteRoot = new URL("../", import.meta.url);
const outputRoot = new URL("../../docs/", import.meta.url);
const basePath = "/battery-monitor";
const releaseVersion = process.env.NEXT_PUBLIC_RELEASE_VERSION ||
  `v${(await readFile(new URL("../../VERSION", import.meta.url), "utf8")).trim()}`;
if (!/^v\d+\.\d+\.\d+$/.test(releaseVersion)) {
  throw new Error("Invalid release version for the design gallery");
}

const workerUrl = new URL("dist/server/index.js", siteRoot);
workerUrl.searchParams.set("export", `${process.pid}-${Date.now()}`);
const { default: worker } = await import(workerUrl.href);

const response = await worker.fetch(
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

if (!response.ok) {
  throw new Error(`Static render failed with HTTP ${response.status}`);
}

let html = await response.text();
html = html
  .replaceAll(
    "http://localhost:3000",
    `https://laleoarrow.github.io${basePath}`,
  )
  .replaceAll('"/_next/', `"${basePath}/_next/`)
  .replaceAll("url(/_next/", `url(${basePath}/_next/`)
  .replaceAll('"/favicon.png', `"${basePath}/favicon.png`)
  .replaceAll('"/og.png', `"${basePath}/og.png`)
  .replaceAll('"/wattson-popover-real.png', `"${basePath}/wattson-popover-real.png`)
  .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
  .replace(/<link\b(?=[^>]*\brel="modulepreload")[^>]*\/?>/gi, "")
  .replace(
    /<button\b(?=[^>]*\bclass="copy-button")[^>]*>[\s\S]*?<\/button>/gi,
    "",
  );

for (const required of [
  "See where",
  "Download DMG",
  "Download PKG",
  "Community build",
]) {
  if (!html.includes(required)) {
    throw new Error(`Static render is missing required content: ${required}`);
  }
}

await mkdir(outputRoot, { recursive: true });
await Promise.all([
  rm(new URL("_next/", outputRoot), { force: true, recursive: true }),
  rm(new URL("favicon.png", outputRoot), { force: true }),
  rm(new URL("og.png", outputRoot), { force: true }),
  rm(new URL("wattson-popover-real.png", outputRoot), { force: true }),
  rm(new URL("index.html", outputRoot), { force: true }),
  rm(new URL("404.html", outputRoot), { force: true }),
  rm(new URL(".nojekyll", outputRoot), { force: true }),
]);
await cp(
  new URL("dist/client/_next/static/css/", siteRoot),
  new URL("_next/static/css/", outputRoot),
  { recursive: true },
);
await cp(
  new URL("dist/client/_next/static/_vinext_fonts/", siteRoot),
  new URL("_next/static/_vinext_fonts/", outputRoot),
  { recursive: true },
);
await cp(new URL("dist/client/favicon.png", siteRoot), new URL("favicon.png", outputRoot));
await cp(new URL("dist/client/og.png", siteRoot), new URL("og.png", outputRoot));
await cp(
  new URL("dist/client/wattson-popover-real.png", siteRoot),
  new URL("wattson-popover-real.png", outputRoot),
);
await writeFile(new URL("index.html", outputRoot), html, "utf8");
await writeFile(new URL("404.html", outputRoot), html, "utf8");
await writeFile(new URL(".nojekyll", outputRoot), "", "utf8");

// Versioned artwork is independent of installer assets and historical Pages.
const gallery = new URL(`../../design/releases/${releaseVersion}/`, import.meta.url);
let hasGallery = false;
try {
  await readFile(new URL("index.html", gallery), "utf8");
  hasGallery = true;
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (hasGallery) {
  await cp(gallery, new URL(`design/${releaseVersion}/`, outputRoot), { recursive: true });
}

const emitted = await readFile(new URL("index.html", outputRoot), "utf8");
if (emitted.includes('"/_next/') || emitted.includes("url(/_next/")) {
  throw new Error("Static page contains an unscoped Next.js asset path");
}
for (const forbidden of [
  "<script",
  'rel="modulepreload"',
  "vinext.navigationRuntime",
  'class="copy-button"',
]) {
  if (emitted.includes(forbidden)) {
    throw new Error(`Static page contains unsupported runtime content: ${forbidden}`);
  }
}
for (const expectedUrl of [
  "https://laleoarrow.github.io/battery-monitor/og.png",
  "/battery-monitor/favicon.png",
]) {
  if (!emitted.includes(expectedUrl)) {
    throw new Error(`Static page contains an incorrect metadata URL: ${expectedUrl}`);
  }
}

console.log(`Exported GitHub Pages site to ${outputRoot.pathname}`);
