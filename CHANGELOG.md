# Changelog

All notable changes to AIPointer are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The project was originally scaffolded on **2026-05-13** and tagged **v1.0.0** on
the same day after a focused build sprint.

---

## [1.0.0] — 2026-05-13

Public-ready release. Single-shot vision Q&A overlay turned into a 4-provider,
agentic, voice-enabled AI cursor companion.

### Added — providers

- **OpenRouter** as the primary provider (Gemini 3 Flash by default, `:online`
  for web-grounded answers).
- **Anthropic** direct integration (Claude Haiku 4.5 / Sonnet 4.6, Messages API
  with full `tool_use` streaming parse).
- **OpenAI** direct integration (GPT-5-mini / GPT-5).
- **Google Gemini** direct integration (Gemini 2.5 Flash / Pro,
  `streamGenerateContent` SSE, function calling, Google Search grounding).
- Automatic provider fallback chain (OpenRouter → Anthropic → OpenAI → Gemini)
  on retryable HTTP errors.
- Smart per-tier model selection: long-form templates auto-bump to the
  capable model.

### Added — agentic tools (function calling, approval-gated)

- `fetch_url(url)` — fetch HTML, extract OG meta + body text.
- `read_clipboard()` — explicit clipboard read.
- `open_url(url)` — open in default browser. Approval required.
- `copy_to_clipboard(text)` — write to clipboard. Approval required.
- `save_document(suggested_name?, content?)` — open native Save dialog. Overlay
  is auto-lowered while the dialog is open so it can't disappear behind the
  always-on-top window. Approval required.
- `reveal_in_finder(path?)` — open Finder/Explorer at workspace path. Approval
  required.
- Inline green-check / red-x approval card surfaced in the response area;
  optional "auto-approve actions" toggle in settings.

### Added — templates (slash commands + implicit prose triggers)

- `/summary` — long structured doc with title, key points, detail, sources.
- `/brief` — TL;DR + 3-5 bullets.
- `/translate` — clean translation block.
- `/explain` — in-short / why / how / example.
- `/code` — answer + fenced code.
- `/improve` — rewritten + change log.
- `/define` — dictionary entry with pronunciation.
- `/solve` — math/logic with stepwise derivation.
- `/reply` — three reply variants (casual / professional / direct).
- `/identify` — bolded ID + confidence + visual reasons + sources.

### Added — voice

- Microphone input via Web Audio MediaRecorder with voice-activity detection
  (auto-stops after 1.5 s of silence). Live pulse-ring intensity indicator.
- Transcription routed through Gemini → OpenAI Whisper → OpenRouter, with
  optional explicit language hint.
- Read-aloud (TTS) for the response: OpenAI `gpt-4o-mini-tts` → Gemini
  `gemini-2.5-flash-preview-tts` → OpenRouter, decoded inline.
- 17-language picker in settings (auto-detect + 16 explicit languages).

### Added — UI & UX

- **Single morphing box** combining input, optional clipboard chip, autocomplete
  dropdown, scrollable response area, and a solid action footer.
- **Bottom pill** that auto-collapses to a status dot and expands on hover;
  click triggers AI mode just like the long-press hotkey. Cursor hit-zone
  detection keeps the click-through overlay responsive.
- **Intro splash** — branded pulsing-halo animation on first launch.
- **Custom About window** (replacing the unreliable macOS system About panel
  for dock-hidden apps).
- **Draggable box** with a grip handle and drag-from-empty-area, viewport-sized
  constraints.
- **User profile** in settings (name + role + preferred reply language) gets
  inlined into the system prompt for personalised replies.
- **System tray** with branded entries: Trigger AIPointer, Settings,
  Privacy Policy, Check for updates, Install update (contextual, appears
  only when a download is pending), About AIPointer v1.0.0,
  Open aipointer.app, Open GitHub repo, Built by Mario Simic,
  Powered by Skales, Quit.
- **Privacy Policy link** in the Settings About disclaimer, opening
  `https://aipointer.app/privacy` via the main process. Disclaimer
  rewritten as three short paragraphs explicitly covering screenshot,
  clipboard, prompt, voice in/out, and profile data flows.
- **8-item FAQ accordion** in settings: how-to-invoke, provider choice, saving,
  commands, privacy, fallback, tools/approvals, voice.
- **Light / dark theme inversion** based on `prefers-color-scheme`, with a
  consistent neutral-gray base (no blue tint).

### Added — memory & persistence

- Multi-turn session continuity within a single AI mode session.
- Optional JSON + Tariq-style A4 HTML transcript saved on dismiss to
  `<workspace>/sessions/`.
- `/history` slash command lists the last 20 saved sessions; click reveals in
  Finder/Explorer.
- Configurable context token budget (default 8 000) with automatic
  oldest-first turn truncation that always preserves the system message and the
  initial screenshot-carrying user message.
- "Clear history" action with file count feedback in settings.

### Added — providers & settings

- Settings UI split into 10 sections: Providers, Behaviour, Memory, Workspace,
  Profile, Input, Capabilities, Updates, About, How to use & FAQ.
- Custom user-selectable trigger hotkey (Right-Cmd / Right-Ctrl / Right-Alt /
  Right-Shift). Setting is read every keydown so changes take effect without
  restart.
- Workspace folder picker with overlay auto-lowering for native dialog
  visibility.
- **Personalize prompts** toggle in the Profile section (default off). When
  off, the user profile is never injected into the system prompt and is
  never sent to the chosen AI provider. GDPR-friendly default.
- **Auto-check for updates** toggle in the Updates section (default on).
  Controls only the scheduled background check; manual "Check for updates"
  from the tray menu works regardless.

### Added — branding & assets

- Programmatically generated 1024×1024 app icon (lime dot in dark capsule with
  halo and specular highlight), rendered from inline SVG via Sharp at startup
  and mirrored to `assets/icon.png` for `electron-builder`.
- Refined tray icon (open ring + filled center dot) as a macOS template image.
- Custom About window with light/dark adaptation, branded links to
  `aipointer.app`, `github.com/talentsache/aipointer`, `github.com/talentsache`,
  and `skales.app`. Draggable, ESC-dismissible.

### Added — auto-update + release tooling

- Custom auto-updater (no `electron-updater` dependency) that fetches
  `https://aipointer.app/updates/latest.json`, compares semver, downloads
  the platform-specific installer to a temp folder, verifies a 128-char
  hex SHA-512, and hands off to the OS-native installer (Windows NSIS
  silent, macOS DMG open, Linux file manager). First check 30 seconds
  after launch, then once every 24 hours. 401 / 403 / 404 fail silently
  on the background path; manual checks surface a clear error.
- `electron/updater/` module split into `types.ts`, `check.ts`,
  `download.ts`, `install.ts`, `index.ts`. Renderer only sees state
  snapshots over the `updates:state` IPC channel.
- `scripts/release-build.sh` end-to-end release script: raises the open-file
  ulimit, builds all targets, computes hex SHA-512 for every artifact,
  generates `latest.json` and the matching electron-builder yml files
  (`latest-mac.yml`, `latest.yml`, `latest-linux.yml`), organizes
  everything into `release/release-artifacts/` with an upload checklist.
  Supports `--mac`, `--win`, `--linux`, `--no-sign`, `--no-notarize`.
- `electron-builder.yml` rewritten with hardened-runtime entitlements,
  Developer ID Application identity, conditional notarization gated on
  the Apple env vars, and a `publish.url` pointing at the AIPointer
  update channel.
- Build entitlements extended with `allow-jit`, `allow-unsigned-executable-memory`,
  `allow-dyld-environment-variables`, `disable-library-validation`,
  `device.audio-input`, and `automation.apple-events`. Camera left
  explicitly false.

### Added — provenance & DNA

- `AIPOINTER_PROVENANCE` constant exported from the main entry.
- Inline HTML watermark embedded in every saved document via the save template.
- Hidden Tailwind class `ms-aipointer-authentic` referenced from a one-pixel
  span in the About window.
- Hidden `/origin` slash command that prints the authorship card.
- PNG metadata (Software + Author XMP tag) embedded in the generated icon.
- System-prompt provenance directive entangled with the identity block so it
  can't be removed without breaking the bot's self-knowledge replies.
- `docs/AUTHORSHIP.md` documenting all of the above.

### Changed

- System prompt rewritten three times across the sprint, finalised as a
  multi-section directive covering self-knowledge, scope, tool guidance,
  implicit template routing, conversation continuity, and the Skales
  out-of-scope referral.
- System prompt's "Tool output handling" section rewritten as an explicit
  data-vs-instruction contract that covers tool output, screenshot, and
  clipboard inputs.
- Settings storage migrated from a single `openrouterApiKey` legacy field to a
  full `providers` object with per-provider toggle + key, plus
  `userProfile`, `voiceLanguage`, `triggerHotkey`, `memorySaveEnabled`,
  `maxContextTokens`, `autoApproveTools`, `personalizePrompts`, and
  `autoCheckUpdates`.
- Provider router refactored from a single OpenRouter-only client into a
  pluggable `ProviderClient` interface with four implementations sharing a
  common streaming-tool-call accumulator.
- Production Content Security Policy is now strict and provider-specific.
  Allowed `connect-src` hosts: openrouter.ai, api.anthropic.com,
  api.openai.com, generativelanguage.googleapis.com, aipointer.app.
  Production drops `unsafe-eval` from `script-src`. Dev keeps a permissive
  policy in `renderer/index.html` for Vite HMR; production is injected by
  a `transformIndexHtml` plugin at build time.
- `fetch_url` tool now sends a generic Chrome User-Agent per platform so
  fetched pages cannot fingerprint that the request came from AIPointer.
  Provider API calls keep the AIPointer UA where attribution is
  appropriate.
- Tool output wrapping: removed the heuristic regex array that prepended
  a warning header when output "looked like injection". The delimiters
  paired with the system prompt's data-vs-instruction directive are the
  actual defense; the heuristic gave false confidence.

### Security

- Removed an auto-approve bypass that affected destructive tools.
  Read-only tools can still skip the prompt; `open_url`,
  `copy_to_clipboard`, `save_document`, and `reveal_in_finder` always
  require explicit approval.
- Added an SSRF guard to `fetch_url`. DNS-resolved hosts in loopback,
  RFC1918, link-local, ULA, CGNAT, multicast, or cloud-metadata ranges
  are rejected. Manual redirect follow re-checks each hop.
- `reveal_in_finder` is now workspace-bound. Paths outside the configured
  workspace are rejected and the tool falls back to the workspace root.
- API keys are stored via Electron `safeStorage` (Keychain on macOS,
  DPAPI on Windows, libsecret on Linux). Replaces the previous hardcoded
  electron-store encryption key. A per-install random envelope key is
  used for non-key settings.
- Process-level `unhandledRejection` and `uncaughtException` handlers in
  main so a stray network rejection does not silently terminate.
- Content Security Policy meta tag on the renderer (see Changed for the
  production whitelist).
- `will-navigate` and `will-redirect` handlers on overlay windows refuse
  any URL that is not the dev server or the bundled `dist/index.html`.
  Http(s) destinations are routed through `shell.openExternal`.
- 401 / 403 from a provider no longer trigger the fallback chain. The
  auth error surfaces immediately so the user fixes the key in
  `/settings` instead of burning quota across other providers.
- Microphone entitlement is enabled in the macOS build so signed builds
  can capture audio for voice input.
- `copy_to_clipboard` clamps writes to 100 KB and strips ANSI / control
  characters.
- `save_document` sanitizes `suggested_name` before passing it through to
  the native dialog.
- `open_url` approval prompt now shows the full `scheme://host` in the
  prominent label, not only the host, to defeat a
  `google.com.attacker.com` style display trick.
- Overlay windows ship with `sandbox: true` in packaged builds. Dev keeps
  `sandbox: false` for HMR.
- Markdown sanitizer no longer accepts the `style` attribute. Closes a
  background-image exfiltration path that would survive a strict
  `connect-src` because `img-src` needs `data:` for inline images.
- Session metadata stores paths relative to the workspace folder. The
  reveal-in-finder IPC handler resolves the relative path against the
  workspace and refuses any input that escapes the boundary.
- Stream readers in all four providers (OpenRouter, OpenAI, Anthropic,
  Gemini) respect AbortController cancellation. ESC during a stream
  cancels the reader immediately instead of letting the server drain.

### Removed

- The original "settings modal" pattern (a small centered dialog) — replaced
  with the full 720 × 720 settings panel.
- Per-query "primary / fallback model" pickers — replaced with automatic
  per-provider model selection so the user never has to think about model IDs.

### Fixed

- macOS Save dialog appearing behind the always-on-top overlay (overlay is now
  auto-lowered for the dialog's lifetime).
- Light/dark theme regression where the overlay's dark glass would invert
  incorrectly on certain `prefers-color-scheme` transitions — now driven by an
  explicit `.dark` class on `<html>`.
- Slash command Enter required two presses to execute — now executes on a single
  Enter when the input exactly matches a command.
- Bottom pill not responding to hover/click despite `pointer-events-auto`
  because the parent window was click-through — now toggles
  `setIgnoreMouseEvents` based on cursor hit-zone.
- Drag constraints too tight (~360 px) — now viewport-sized, free drag within
  the display.

### Added — late v1.0.0 polish (same-day 2026-05-13)

- **Region screenshot gesture.** While the box is open, holding the trigger key
  again switches the overlay into selection-arm mode (cursor → crosshair, hint
  pill "Drag to capture a region"). Left-mouse drag draws a lime-bordered
  selection rectangle with live size readout; release captures exactly that
  region (via `sharp.extract` against the display thumbnail) and replaces the
  default 1024×768 cursor-centered crop for the current query. ESC mid-drag
  cancels cleanly without dismissing the box. Multi-display aware — the rect's
  display-local coords convert through `display.workArea` offsets.
- **Voice-first conversation mode** (Settings → Behaviour, default off). When
  on, triggering AIPointer opens the box already listening: VAD-stopped
  transcript auto-submits, the response is read back via TTS, the mic
  re-opens for the next turn. A compact phase pill below the drag handle
  shows the current leg (Listening → Thinking → Speaking → Done · say a
  follow-up). The mic-level pulses on the Listening dot. ESC breaks the
  loop. Robust against double-arm, double-TTS, and stale closures via
  three guard refs (`audioActiveRef`, `spokenResponseRef`, `armNextRef`).
- **Per-provider key tester.** Each provider card in Settings has a `Test`
  button next to the API-key input. The main process hits a provider-specific
  validation endpoint via Electron's `net` module (OpenRouter `/credits`,
  Anthropic `/models`, OpenAI `/models`, Gemini `/models?key=`) and surfaces
  the result inline (✓ valid, ✕ with error message). For OpenRouter the
  success label includes the remaining balance, e.g. "$3.42 left", parsed
  from `total_credits - total_usage`. The result is invalidated automatically
  when the user edits the key.
- **Gemini-inspired cursor halo.** The single lime gradient was replaced with
  a three-layer composition: outer brand-lime glow (8 px blur, dezenter than
  before), middle near-white luminous ring, inner 6 × 6 px white pixel-pip
  with a thin lime outline. Anchors the eye to the exact OS cursor pixel
  even on busy backgrounds while staying brand-consistent.
- **Live clipboard polling.** While AI mode is active, the main process polls
  the OS clipboard every 400 ms via a dedicated `pollClipboardIfChanged()`
  helper. New copies (Cmd+C in another app) surface the clipboard chip in
  the box within half a second. Clicking the X on the chip "dismisses" the
  current clipboard — polling and the next submit both ignore it until the
  text actually changes.
- **Tray-menu cleanup.** Removed the "Toggle DevTools" entry (only useful for
  developers; end users shouldn't see it). DevTools remain accessible via
  `Cmd+Opt+I` when needed.
- **/help expanded** with sections on "What AIPointer sees" (screenshot +
  clipboard + region awareness), "What AIPointer can do" (tools with auto vs
  approval markers), "Gestures" (full keyboard/mouse map), and "Privacy".
- **FAQ expanded** with 8 new entries: region screenshots, what AIPointer
  sees, tool capabilities, multi-display behaviour, power/perf impact,
  uninstall paths, keyboard shortcuts, voice-first mode.

### Fixed — late v1.0.0 polish (same-day 2026-05-13)

- **Flicker root-cause hunt.** Three independent contributors found and
  killed:
  - `useLinkMetas.reset` returned a fresh function identity on every render,
    so the dependent `useEffect([hasResponse, resetMetas])` fired in a tight
    loop (Maximum update depth exceeded). `reset` is now `useCallback`-
    stabilised and `setMetas` is idempotent on empty state.
  - `motion.div` in PromptInput had `layout` (= true), spring-animating
    every height change. With the new 400 ms clipboard poll surfacing the
    chip on a delay, the box pumped vertically. Changed to `layout="position"`
    so position changes still animate but size changes apply instantly.
  - `setOverlayInteractive` in the main process called
    `setIgnoreMouseEvents` + `setFocusable` + `focus()`/`blur()` on every
    invocation, even when the state hadn't changed. On macOS each of those
    triggers a window-frame repaint. Now caches the last-applied state per
    display and no-ops if unchanged. Window is also permanently focusable
    instead of toggled per hover.
- **Cursor-hit-test hysteresis.** Box hover test now uses 14 px halo to
  enter, 80 px to leave. Without hysteresis cursor wobble at the box edge
  flipped `boxHovered` every frame, toggling `setIgnoreMouseEvents` and
  causing visual flicker. The wider leave-halo also covers the natural lag
  between cursor position (33 ms IPC) and box position during a fast drag.
- **Drag-then-input dead.** After dragging the box once, the input field
  became unclickable and a second drag was impossible. Root cause: the
  forwardedRef pointed to the OUTER motion.div (positioned at the entry
  anchor via `x, y` props), but drag-translation is applied to the INNER
  motion.div via CSS transform. `getBoundingClientRect()` on the outer
  returned the original anchor position, so the App.tsx hit-test thought
  the cursor was outside the box, flipped `boxHovered` to false, and the
  overlay went click-through. Moved `ref={forwardedRef}` onto the inner
  motion.div so its bounds follow the visible (transformed) position.
- **Settings won't open on multi-display.** The `onSettingsOpen` IPC
  listener filtered on `isPrimary`, so requests from the tray menu silently
  opened settings on the primary display when the user was on a secondary
  one. The filter is gone — settings opens on whichever overlay's renderer
  receives the broadcast first.
- **Splash blocked browser access on first run.** First-run UX auto-opened
  Settings on top of the splash, so the user couldn't reach Chrome to copy
  their OpenRouter key. Auto-open now waits for `splashDone`, and an
  `OverlaySettingsMode` IPC lowers every overlay's `alwaysOnTop` level
  while Settings is open so Cmd+Tab to a browser actually works.
- **Outside-click dismiss didn't fire on a click-through overlay.** The
  React backdrop handler was useless because `setIgnoreMouseEvents(true)`
  forwarded the clicks to the underlying app. Now the main-process uiohook
  mouse handler reads the current box bounds (broadcast from the renderer
  on every layout change) and decides single- vs double-click dismiss
  itself, governed by the new `dismissOnDoubleClick` setting (default on).
- **TTS-on-OpenRouter-only.** `useTTS` falls back to the Web Speech API
  whenever the provider TTS call errors (OpenRouter has no `/audio/speech`
  endpoint at all). The Read-aloud button now always does something useful.
- **White-on-white markdown in dark mode.** `html.dark { color: ... }` in
  `globals.css` overrides the cascade so streamed Markdown is readable on
  the white card.
- **Clipboard-context auto-fills despite explicit dismiss.** X-clicking the
  chip now stores the dismissed text as `dismissedClipboard` and both the
  poller and the next `runQuery` skip it until the OS clipboard contents
  change. No more sneaking dismissed text back into prompts.

---

## [0.3.0] — 2026-05-13

Pre-v1.0 polish + agentic foundation.

### Added

- Initial slash command system with autocomplete dropdown (5 commands).
- First six templates (`/summary`, `/brief`, `/translate`, `/explain`,
  `/code`, `/improve`).
- OpenRouter `:online` routing for web-grounded answers.
- Link card previews with OG image fetching.
- HTML / Markdown / PDF document save via native dialog.
- Markdown response rendering with `react-markdown`, GFM, and sanitised inline
  HTML for richer Gemini outputs (tables, callouts, cards).
- Tariq-style A4 HTML save template with print-ready CSS and KPI / card / step
  primitives.

### Changed

- Response rendering moved from plain text to Markdown + selective HTML inline.
- Save / Copy buttons moved from a floating absolute overlay into a solid
  footer row beneath the response so they no longer cover the text.

### Fixed

- Settings modal "navy/lila" colour (saturated slate) replaced with neutral
  gray.

---

## [0.2.0] — 2026-05-13

### Added

- Tool calling foundation: shared agentic loop, JSON-schema tool declarations,
  inline activity rendering ("Reading example.com", "Saving document").
- Workspace folder picker.
- Session save (JSON + HTML) toggle.

### Changed

- Box position pinned to the cursor at trigger time, then user-draggable.
- Settings refactored from "modal" to full panel.

---

## [0.1.0] — 2026-05-13

Initial scaffold (Phase 1 per the original brief).

### Added

- Electron + React + TypeScript + Vite project structure with
  `vite-plugin-electron`.
- Transparent always-on-top overlay window, one per display.
- Long-press global hook via `uiohook-napi` (Right-Cmd hold for 200 ms or
  right-mouse hold for 250 ms).
- 60 Hz cursor tracking and the lime-green halo with spring-animated follow.
- Vision Q&A pipeline: screenshot capture (1024 × 768 around cursor),
  base64 JPEG, clipboard context, OpenRouter streaming chat completions.
- macOS Accessibility + Screen Recording permission detection and prompts.
- Single OpenRouter-only provider with `gemini-3-flash-preview`.

---

[1.0.0]: https://github.com/talentsache/aipointer/releases/tag/v1.0.0
[0.3.0]: https://github.com/talentsache/aipointer/releases/tag/v0.3.0
[0.2.0]: https://github.com/talentsache/aipointer/releases/tag/v0.2.0
[0.1.0]: https://github.com/talentsache/aipointer/releases/tag/v0.1.0
