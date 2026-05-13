import sharp from 'sharp';
import { app, nativeImage } from 'electron';
import { promises as fs } from 'node:fs';
import { join } from 'node:path';
import type { NativeImage } from 'electron';

// Two icons are generated programmatically from SVG at first use:
//
//  - TRAY icon: monochrome black-on-transparent, sized 22×22 (+ 44×44 retina),
//    marked as a macOS template image so the OS auto-inverts in light/dark
//    menubars. It is just the AIPointer logo silhouette: an open ring around
//    a centred dot.
//
//  - APP icon: full-colour 1024×1024 PNG with the lime accent dot inside a
//    dark capsule and a soft halo. Used by the macOS About panel and any
//    other place that asks for an iconPath (Tray.setImage fallback, etc.).
//
// Both are cached in userData. A symlink-ish copy is also written to
// assets/icon.png if that path is missing, so electron-builder can pick the
// real icon up at dist time without any extra setup.

const TRAY_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 22">
  <circle cx="11" cy="11" r="8" fill="none" stroke="#000" stroke-width="2"/>
  <circle cx="11" cy="11" r="3" fill="#000"/>
</svg>`;

const APP_ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="halo" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#a7f56b" stop-opacity="0.45"/>
      <stop offset="50%" stop-color="#a7f56b" stop-opacity="0.12"/>
      <stop offset="80%" stop-color="#a7f56b" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="body" cx="35%" cy="32%" r="78%">
      <stop offset="0%" stop-color="#2c2c31"/>
      <stop offset="100%" stop-color="#0c0c0d"/>
    </radialGradient>
    <radialGradient id="dot" cx="42%" cy="38%" r="65%">
      <stop offset="0%" stop-color="#d6ffa8"/>
      <stop offset="45%" stop-color="#a7f56b"/>
      <stop offset="100%" stop-color="#6cc134"/>
    </radialGradient>
    <radialGradient id="dotShine" cx="50%" cy="40%" r="50%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="60%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <!-- Outer soft halo, gives the icon presence on busy backgrounds. -->
  <circle cx="512" cy="512" r="510" fill="url(#halo)"/>

  <!-- Main body: dark capsule, very subtle stroke for crispness on light bgs. -->
  <circle cx="512" cy="512" r="384" fill="url(#body)"/>
  <circle cx="512" cy="512" r="384" fill="none" stroke="#3a3a42" stroke-width="2.5" opacity="0.9"/>

  <!-- Inner accent dot (the "AI pointer"). -->
  <circle cx="512" cy="512" r="156" fill="url(#dot)"/>
  <!-- Specular highlight on the dot. -->
  <ellipse cx="478" cy="468" rx="78" ry="60" fill="url(#dotShine)"/>
</svg>`;

let cachedTrayImage: NativeImage | null = null;
let cachedAppIconPath: string | null = null;

async function ensureDir(path: string): Promise<void> {
  try {
    await fs.mkdir(path, { recursive: true });
  } catch {
    /* ignore */
  }
}

export async function getTrayIcon(): Promise<NativeImage> {
  if (cachedTrayImage) return cachedTrayImage;
  const cacheDir = app.getPath('userData');
  await ensureDir(cacheDir);
  const path22 = join(cacheDir, 'tray-icon-Template.png');
  const path44 = join(cacheDir, 'tray-icon-Template@2x.png');

  await Promise.all([
    sharp(Buffer.from(TRAY_SVG)).resize(22, 22).png().toFile(path22),
    sharp(Buffer.from(TRAY_SVG)).resize(44, 44).png().toFile(path44),
  ]).catch(() => undefined);

  const image = nativeImage.createFromPath(path22);
  try {
    const retina = nativeImage.createFromPath(path44);
    if (!retina.isEmpty()) {
      image.addRepresentation({
        scaleFactor: 2.0,
        width: 44,
        height: 44,
        buffer: retina.toPNG(),
      });
    }
  } catch {
    /* ignore */
  }
  image.setTemplateImage(true);
  cachedTrayImage = image;
  return image;
}

export async function getAppIconPath(): Promise<string> {
  if (cachedAppIconPath) return cachedAppIconPath;
  const cacheDir = app.getPath('userData');
  await ensureDir(cacheDir);
  const targetPath = join(cacheDir, 'aipointer-icon.png');
  try {
    await sharp(Buffer.from(APP_ICON_SVG))
      .resize(1024, 1024)
      // Embed authorship metadata in the PNG itself — see docs/AUTHORSHIP.md.
      // Inert: travels with the file, not used at runtime.
      .withMetadata({
        exif: {
          IFD0: {
            Software: 'AIPointer 1.0.0',
            Artist: 'Mario Simic',
            Copyright: '© 2026 Mario Simic — MIT — github.com/talentsache/aipointer',
            ImageDescription:
              'aipointer/v1.0.0/ms/talentsache/skales/20260513 — aipointer.app',
          },
        },
      })
      .png({ compressionLevel: 9 })
      .toFile(targetPath);
    cachedAppIconPath = targetPath;
    // Also mirror to assets/icon.png if the build asset is missing — that's
    // the file electron-builder reads for distribution builds.
    void mirrorToAssets(targetPath).catch(() => undefined);
    return targetPath;
  } catch (err) {
    console.error('[icon] failed to render app icon', err);
    throw err;
  }
}

async function mirrorToAssets(sourcePath: string): Promise<void> {
  // Resolve assets/icon.png relative to the app's resources/source root.
  // In dev (vite-plugin-electron) main runs from dist-electron/, so go up
  // one level to find <repo>/assets/. In a packaged build the resources
  // path is sealed, so we skip silently.
  const candidates = [
    join(app.getAppPath(), 'assets', 'icon.png'),
    join(__dirname, '..', 'assets', 'icon.png'),
  ];
  for (const target of candidates) {
    try {
      await fs.stat(target);
      return; // already exists, don't overwrite
    } catch {
      // missing — try to write
      try {
        await fs.mkdir(join(target, '..'), { recursive: true });
        await fs.copyFile(sourcePath, target);
        return;
      } catch {
        // not writable here; try the next candidate
        continue;
      }
    }
  }
}
