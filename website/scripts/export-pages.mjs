import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";

const siteRoot = new URL("../", import.meta.url);
const outputRoot = new URL("../../docs/", import.meta.url);
const basePath = "/battery-monitor";

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
  .replaceAll('"/og.png', `"${basePath}/og.png`);

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

await rm(outputRoot, { force: true, recursive: true });
await mkdir(outputRoot, { recursive: true });
await cp(new URL("dist/client/_next/", siteRoot), new URL("_next/", outputRoot), {
  recursive: true,
});
await cp(new URL("dist/client/favicon.png", siteRoot), new URL("favicon.png", outputRoot));
await cp(new URL("dist/client/og.png", siteRoot), new URL("og.png", outputRoot));
await writeFile(new URL("index.html", outputRoot), html, "utf8");
await writeFile(new URL("404.html", outputRoot), html, "utf8");
await writeFile(new URL(".nojekyll", outputRoot), "", "utf8");

const emitted = await readFile(new URL("index.html", outputRoot), "utf8");
if (emitted.includes('"/_next/') || emitted.includes("url(/_next/")) {
  throw new Error("Static page contains an unscoped Next.js asset path");
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
