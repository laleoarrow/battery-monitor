"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowUpRight,
  CircleAlert,
  FileArchive,
  PackageOpen,
  SquareTerminal,
} from "lucide-react";

const GITHUB_REPO = "https://github.com/laleoarrow/battery-monitor";
const RELEASES_URL = `${GITHUB_REPO}/releases/latest`;
const RELEASE_API =
  "https://api.github.com/repos/laleoarrow/battery-monitor/releases/latest";
const FALLBACK_VERSION = "v3.0.16";
const FALLBACK_ASSET_BASE = `${GITHUB_REPO}/releases/download/${FALLBACK_VERSION}`;
const HOMEBREW_COMMAND = "brew install --cask laleoarrow/tap/wattson";

type ReleaseAsset = {
  browser_download_url: string;
  name: string;
};

type LatestRelease = {
  assets?: ReleaseAsset[];
  html_url?: string;
  tag_name?: string;
};

type ReleaseDetails = {
  dmgUrl: string;
  htmlUrl: string;
  pkgUrl: string;
  source: "fallback" | "live";
  version: string;
};

const fallbackRelease: ReleaseDetails = {
  dmgUrl: `${FALLBACK_ASSET_BASE}/Wattson-${FALLBACK_VERSION}-macos-universal.dmg`,
  htmlUrl: RELEASES_URL,
  pkgUrl: `${FALLBACK_ASSET_BASE}/Wattson-${FALLBACK_VERSION}-macos-universal.pkg`,
  source: "fallback",
  version: FALLBACK_VERSION,
};

function ReleaseLink({
  children,
  className,
  href,
}: {
  children: React.ReactNode;
  className: string;
  href: string;
}) {
  return (
    <a className={className} href={href} rel="noreferrer" target="_blank">
      {children}
      <ArrowUpRight aria-hidden="true" className="button-arrow" size={15} />
    </a>
  );
}

export default function Home() {
  const [release, setRelease] = useState<ReleaseDetails>(fallbackRelease);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const controller = new AbortController();

    async function loadLatestRelease() {
      try {
        const response = await fetch(RELEASE_API, {
          headers: { Accept: "application/vnd.github+json" },
          signal: controller.signal,
        });

        if (!response.ok) {
          throw new Error("Latest release unavailable");
        }

        const latest = (await response.json()) as LatestRelease;
        const assets = latest.assets ?? [];
        const htmlUrl = latest.html_url || RELEASES_URL;
        const dmg = assets.find((asset) => asset.name.toLowerCase().endsWith(".dmg"));
        const pkg = assets.find((asset) => asset.name.toLowerCase().endsWith(".pkg"));

        setRelease({
          dmgUrl: dmg?.browser_download_url || htmlUrl,
          htmlUrl,
          pkgUrl: pkg?.browser_download_url || htmlUrl,
          source: "live",
          version: latest.tag_name || FALLBACK_VERSION,
        });
      } catch (error) {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          setRelease(fallbackRelease);
        }
      }
    }

    void loadLatestRelease();
    return () => controller.abort();
  }, []);

  const versionLabel = useMemo(
    () => release.version.replace(/^v/i, "v"),
    [release.version],
  );

  async function copyHomebrewCommand() {
    try {
      await navigator.clipboard.writeText(HOMEBREW_COMMAND);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      setCopied(false);
    }
  }

  return (
    <main>
      <a className="skip-link" href="#content">
        Skip to content
      </a>

      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Wattson home">
          <span aria-hidden="true" className="brand-cell">
            <span className="brand-charge" />
          </span>
          <span>Wattson</span>
        </a>

        <nav aria-label="Primary navigation" className="main-nav">
          <a href="#features">Features</a>
          <a href="#install">Install</a>
          <a href={GITHUB_REPO} rel="noreferrer" target="_blank">
            GitHub
          </a>
        </nav>

        <a className="header-download" href="#install">
          Get Wattson
          <span aria-hidden="true">↓</span>
        </a>
      </header>

      <div id="content">
        <section className="hero" id="top">
          <div aria-hidden="true" className="hero-glow hero-glow-blue" />
          <div aria-hidden="true" className="hero-glow hero-glow-orange" />

          <div className="hero-copy">
            <div className="eyebrow">
              <span className="live-dot" />
              Native macOS power monitor
            </div>
            <h1>
              See where
              <br />
              <span>every watt</span> goes.
            </h1>
            <p className="hero-lede">
              Wattson turns battery, adapter, and system load into one calm,
              live map—right from your menu bar.
            </p>
            <div className="hero-actions">
              <ReleaseLink className="button button-primary" href={release.dmgUrl}>
                Download for Mac
              </ReleaseLink>
              <a className="button button-ghost" href="#flow-preview">
                Explore the flow
                <span aria-hidden="true" className="button-arrow">
                  ↓
                </span>
              </a>
            </div>
            <div className="compatibility-line" aria-label="Compatibility">
              <span>macOS 12+</span>
              <span>Apple silicon + Intel</span>
              <span>No telemetry</span>
            </div>
          </div>

          <figure className="app-showcase" id="flow-preview">
            <div aria-hidden="true" className="showcase-shadow" />
            <Image
              alt="The real Wattson menu bar popover showing live power flow, battery, system load, history, and energy mode controls"
              className="real-popover-image"
              height={1530}
              priority
              src="/wattson-popover-real.png"
              unoptimized
              width={864}
            />
            <figcaption>Captured from Wattson’s production AppKit hierarchy.</figcaption>
          </figure>
        </section>

        <section className="signal-strip" aria-label="Product highlights">
          <div>
            <strong>1 s</strong>
            <span>refresh while open</span>
          </div>
          <div>
            <strong>2 min</strong>
            <span>power history</span>
          </div>
          <div>
            <strong>4 states</strong>
            <span>clearly distinguished</span>
          </div>
          <div>
            <strong>0 bytes</strong>
            <span>personal data uploaded</span>
          </div>
        </section>

        <section className="features section-shell" id="features">
          <div className="section-intro">
            <span className="section-kicker">Clarity without the clutter</span>
            <h2>Power you can actually read.</h2>
            <p>
              Wattson gives the numbers shape, motion, and context—so you can
              tell charging from drawing power at a glance.
            </p>
          </div>

          <div className="feature-grid">
            <article className="feature-card feature-card-wide">
              <div aria-hidden="true" className="feature-visual lane-visual">
                <span className="lane-dot lane-dot-blue" />
                <span className="lane-track lane-track-blue" />
                <span className="lane-core" />
                <span className="lane-track lane-track-orange" />
                <span className="lane-dot lane-dot-orange" />
              </div>
              <span className="feature-number">01</span>
              <h3>Power, in motion</h3>
              <p>
                Follow energy from adapter to battery to system load. Charging,
                full, on-battery, and mixed-power states each get a distinct read.
                Adapter, System, and Battery node icons share one optical scale;
                System uses a simplified matching chip glyph while semantic
                source and load colours remain unchanged. The restored
                24-point Medium node artwork uses a diagonal
                adapter plug and a green bracketed charging battery with a
                central lightning mark inside the existing 36-point wells.
              </p>
            </article>

            <article className="feature-card">
              <div aria-hidden="true" className="feature-visual ring-visual">
                <div className="mini-ring">
                  <span>82</span>
                </div>
              </div>
              <span className="feature-number">02</span>
              <h3>Native by design</h3>
              <p>
                The dedicated Menu Bar Icon page uses Wattson’s mark and the
                macOS-style battery glyph across all four complete menu-bar
                appearances. It lists the appearances vertically, one full-width
                option per row: Wattson icon only, Wattson with percentage,
                macOS 26 icon only, and macOS 26 with percentage. Every row previews
                seven real production-rendered states: Battery, Full, Charging,
                Low, Low +
                AC, Saver, and Saver + AC. Every preview uses the real
                BatteryIcon renderer; percentage rows show matching per-state
                values to the left of each glyph. The macOS 26 rows use full-size
                macOS 26 Control Center battery parts from the running system,
                including the 23×12 outline and 11×14 bolt, instead of smaller
                Control Center artwork or generic SF Symbols. Every connected
                state uses the system bolt. In Low Power Mode, only the battery
                fill is yellow; the outline, cap, and bolt keep the menu-bar
                foreground colour. General adds Check for Updates and Check for
                Updates on Launch. Manual checks read GitHub Latest Release and
                open its trusted release page; launch checks default on, stay
                quiet when current or offline, and never download or install
                automatically. The Settings sidebar uses the real
                packaged Wattson app icon instead of a separate ECG-style
                drawing.
              </p>
            </article>

            <article className="feature-card">
              <div aria-hidden="true" className="feature-visual toggle-visual">
                <div className="mini-segment">
                  <span className="selected">Auto</span>
                  <span>Low</span>
                  <span>High</span>
                </div>
              </div>
              <span className="feature-number">03</span>
              <h3>Control in one click</h3>
              <p>
                Settings fits a compact 720×520 window, with General, Menu Bar
                Icon, and Modules arranged for quick scanning.
              </p>
            </article>

            <article className="feature-card feature-card-wide privacy-card">
              <div aria-hidden="true" className="feature-visual privacy-visual">
                <span className="privacy-orbit" />
                <span className="privacy-lock">
                  <i />
                </span>
              </div>
              <span className="feature-number">04</span>
              <h3>Local, always</h3>
              <p>
                Battery and power state stay on your Mac. Wattson has no
                account, analytics, personal telemetry, or data upload. Optional
                update checks contact only GitHub Releases.
              </p>
            </article>
          </div>
        </section>

        <section aria-labelledby="install-title" className="install-section" id="install">
          <div className="install-shell">
            <div className="install-heading">
              <div>
                <span className="section-kicker">Choose your route</span>
                <h2 id="install-title">Put Wattson in your menu bar.</h2>
              </div>
              <div className="release-pill" aria-live="polite">
                <span className="live-dot" />
                <span>{versionLabel}</span>
                <small>
                  {release.source === "live" ? "checked on GitHub" : "bundled stable release"}
                </small>
              </div>
            </div>

            <div aria-label="Installation methods" className="install-panel">
              <article className="install-row install-row-recommended">
                <span aria-hidden="true" className="install-glyph dmg-glyph">
                  <FileArchive size={24} strokeWidth={1.7} />
                </span>
                <div className="install-copy">
                  <span className="recommended-label">Recommended</span>
                  <h3>Disk image</h3>
                  <p>
                    Open the image, then double-click the enclosed
                    <strong> Wattson PKG</strong> and follow macOS Installer.
                  </p>
                </div>
                <ReleaseLink className="install-action primary-action" href={release.dmgUrl}>
                  Download DMG
                </ReleaseLink>
              </article>

              <article className="install-row">
                <span aria-hidden="true" className="install-glyph pkg-glyph">
                  <PackageOpen size={24} strokeWidth={1.7} />
                </span>
                <div className="install-copy">
                  <h3>Package installer</h3>
                  <p>
                    Download the same universal installer package directly,
                    without the disk-image wrapper.
                  </p>
                </div>
                <ReleaseLink className="install-action" href={release.pkgUrl}>
                  Download PKG
                </ReleaseLink>
              </article>

              <article className="install-row install-row-homebrew">
                <span aria-hidden="true" className="install-glyph brew-glyph">
                  <SquareTerminal size={24} strokeWidth={1.7} />
                </span>
                <div className="install-copy">
                  <h3>Homebrew</h3>
                  <p>Install or update from Terminal with the community tap.</p>
                </div>
                <div className="command-box">
                  <code>{HOMEBREW_COMMAND}</code>
                  <button
                    aria-label={
                      copied
                        ? "Homebrew install command copied"
                        : "Copy Homebrew install command"
                    }
                    aria-live="polite"
                    className="copy-button"
                    onClick={copyHomebrewCommand}
                    type="button"
                  >
                    {copied ? "Copied" : "Copy"}
                  </button>
                </div>
              </article>
            </div>

            <aside className="trust-note">
              <div aria-hidden="true" className="trust-mark">
                <CircleAlert size={25} strokeWidth={1.55} />
              </div>
              <div className="trust-copy">
                <span className="trust-eyebrow">Community build · Know what you install</span>
                <p>
                  <strong>Transparent about trust.</strong> The app and helper are
                  ad-hoc signed; the PKG and DMG are unsigned and not
                  Apple-notarized. On macOS 15 or later, first try to open the
                  installer, then use System Settings → Privacy &amp; Security →
                  Open Anyway only if you trust this release. Review the source
                  and compare the provided SHA-256 checksum before installing.
                </p>
              </div>
              <a href={`${GITHUB_REPO}/releases`} rel="noreferrer" target="_blank">
                Inspect releases <span aria-hidden="true">↗</span>
              </a>
            </aside>

            <div className="system-requirements">
              <div>
                <span className="requirement-label">System</span>
                <strong>macOS 12 or later</strong>
                <small>Monterey through the latest macOS</small>
              </div>
              <div>
                <span className="requirement-label">Architecture</span>
                <strong>Apple silicon + Intel</strong>
                <small>Universal support for battery-equipped Macs</small>
              </div>
              <div>
                <span className="requirement-label">Source</span>
                <strong>Open on GitHub</strong>
                <small>Read the code, report issues, or contribute</small>
              </div>
            </div>
          </div>
        </section>

        <section className="closing-section section-shell">
          <div className="closing-mark" aria-hidden="true">
            <span className="closing-cell">
              <i />
            </span>
          </div>
          <span className="section-kicker">A clearer relationship with power</span>
          <h2>Your Mac is already talking.<br />Wattson lets you see it.</h2>
          <ReleaseLink className="button button-primary" href={release.dmgUrl}>
            Download {versionLabel}
          </ReleaseLink>
        </section>
      </div>

      <footer className="site-footer">
        <div className="footer-brand">
          <a className="wordmark" href="#top" aria-label="Wattson home">
            <span aria-hidden="true" className="brand-cell">
              <span className="brand-charge" />
            </span>
            <span>Wattson</span>
          </a>
          <p>A native power-flow monitor for macOS.</p>
        </div>
        <div className="footer-links">
          <a href={GITHUB_REPO} rel="noreferrer" target="_blank">
            Source
          </a>
          <a href={`${GITHUB_REPO}/releases`} rel="noreferrer" target="_blank">
            Releases
          </a>
          <a href={`${GITHUB_REPO}/issues`} rel="noreferrer" target="_blank">
            Issues
          </a>
        </div>
        <p className="footer-note">
          Wattson is an independent community project and is not affiliated
          with Apple Inc.
        </p>
      </footer>
    </main>
  );
}
