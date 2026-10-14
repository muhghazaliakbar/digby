# Prompt: Build "Digby" — a native macOS GUI for the `mole` CLI

Copy everything below this line into your coding agent (Claude Code, Cursor, etc.). Attach `Digby.dc.html` as the visual reference.

---

## Role & goal

You are a senior macOS engineer. Build **Digby**, a native macOS app (SwiftUI, macOS 14+, Apple Silicon + Intel) that is a GUI front-end for the open-source CLI **Mole** (https://github.com/tw93/mole). The app must match the attached design reference `Digby.dc.html` pixel-for-pixel in layout, color, type and motion. Open it in a browser and click through every screen before writing code.

The app never reimplements cleaning logic. It shells out to the `mo` binary, parses its output, and presents it. Read Mole's README and source first and confirm the real subcommands, flags and output format; where this prompt and the repo disagree, the repo wins and you note the difference in `NOTES.md`.

## Naming & attribution

- App name: **Digby**. Bundle ID `com.<yourdomain>.digby`, Homebrew cask `digby-cleaner` (confirm with `brew search digby` before publishing).
- Digby is an unofficial front-end. Do not use "Mole" in the app name, icon or marketing. The About window and README state: "Digby is an independent GUI for the open-source Mole CLI by tw93. Not affiliated with Mole or mole.fit." Link to the repo and comply with its license.
- Sidebar logo: "dg" monogram on accent, subtitle "for Mole CLI".

## Hard rules

1. **Safety first.** Every destructive action is preceded by a scan + review screen. Nothing is deleted without an explicit click on a primary button that shows the size (e.g. "Clean 48.2 GB").
2. Prefer moving to Trash over `rm` wherever the CLI allows it. Uninstall always moves to Trash.
3. Dry run is a first-class toggle on Clean, mapped to the CLI's dry-run flag.
4. Admin tasks use `SMAppService`/a privileged helper or `AuthorizationServices`, asking for the password once per run. Never store the password.
5. If `mo` is not installed, show a first-run screen offering `brew install mole` (fallback: the official `install.sh` script from the repo README) with a copy button, and a "Locate binary…" picker.
6. Every screen shows its equivalent CLI command in the header (`$ mo clean --dry-run`, click to copy). Every action streams its raw CLI output into the bottom Terminal drawer.
7. Respect *Reduce Motion*: replace all movement with ≤150 ms opacity fades.

## Architecture

- SwiftUI + `@Observable` view models, one per module. No third-party UI libraries.
- `MoleRunner` actor: launches `mo` via `Process`, streams stdout/stderr line-by-line as `AsyncStream<String>`, supports cancellation (SIGINT), returns exit code. Uses JSON output if the CLI offers it; otherwise a dedicated, unit-tested parser per subcommand.
- `TerminalLog` shared store: ring buffer (last 500 lines), each line tagged `cmd | ok | warn | dim | default`.
- `DiskInfo` service: free/used space via `URLResourceValues.volumeAvailableCapacityForImportantUsage`, refreshed after every destructive action, with the value animating to the new number.
- `SystemMonitor` service for Status (1 s tick): per-core CPU via `host_processor_info`, memory via `host_statistics64`, network via `getifaddrs` deltas, disk I/O via IOKit, battery via IOKit `AppleSmartBattery`, top processes via `proc_pidinfo`. If `mo status` provides these, prefer it.
- Window: single window, min 1080×700, default 1280×820, `.windowStyle(.hiddenTitleBar)` with traffic lights inset 16 px; full-size content view.
- Keyboard: ⌘1–⌘7 switch modules, ⌘J toggles Terminal, ⌘R rescans current module, Esc cancels a running job.
- Unit tests for every parser; UI tests for the Clean flow in dry-run mode.

## Design tokens (match exactly)

**Colors**
| Token | Hex | Use |
|---|---|---|
| bg.app | #0E1013 | main content |
| bg.sidebar | #0A0B0E | sidebar |
| bg.drawer | #08090B | terminal |
| bg.footer | #0C0D10 | action bars |
| surface | #14171C | cards |
| surface.raised | #1A1E24 | rows inside cards, hover |
| surface.track | #1C2027 | progress tracks |
| border | #22262D | card borders |
| border.subtle | #1C1F25 / #1E2229 | dividers |
| border.strong | #2A2F37 | secondary buttons, off toggles |
| text.primary | #E8EAED | |
| text.secondary | #B8BEC7 | paths, values |
| text.muted | #8A919C | descriptions |
| text.faint | #5D6470 | hints, timestamps |
| accent | #3D8BFF (hover #5A9CFF, light #7AB0FF) | primary actions, selection |
| accent.selection | #16243A | selected nav/list row |
| success | #3DDC97 | freed space, done |
| warning | #FFB547 | admin badge, "recent" |
| danger | #FF5C5C | uninstall |
| violet | #7C6CFF | E-cores, developer junk |
| cyan | #2BC4E8 | browser, compressed mem |
| orange | #FF7A59 | trash |
| pink | #E86BB0 | support files |

Category palette order (rings, treemap): accent, violet, cyan, success, warning, orange, pink, #9AA4B2.

**Type**: UI = Familjen Grotesk (bundle it; fallback SF Pro). Numbers, paths, commands = JetBrains Mono (bundle it; fallback SF Mono). Sizes: page title 19/600, hero 28/600, card label 11.5/600 uppercase +0.08em tracking, body 13.5–14.5, metadata 12–12.5, big numbers 26–40 mono 500 with −1 to −1.5 tracking.

**Shape & spacing**: window radius 14, cards 14, rows 8–10, buttons pill (height 42–48), checkboxes 5 (18 px) / 4 (16 px), toggles 36×22. Card padding 20, grid gap 14, page padding 24. Sidebar width 228.

## Motion spec

Use SwiftUI springs; reference values from the design:
- **Page change**: new view fades in from y+10 and blur 4→0, 0.45 s, easeOut (`cubic-bezier(.2,.8,.2,1)`). Header title slides in from x+18.
- **Sidebar selection**: one shared highlight (`matchedGeometryEffect`) glides between items with a slightly overshooting spring (response 0.5, damping 0.7). Active icon scales to 1.12.
- **Stagger**: cards and rows enter from y+14 with 35–70 ms delay per index, capped at 14 items.
- **Buttons**: hover lifts −2 px; press scales to 0.95. Primary idle "Scan" button emits two looping ripple rings (2.4 s, offset 1.2 s).
- **Checkbox/toggle**: knob and check use a bouncy spring (response 0.35, damping 0.55).
- **Toasts**: bottom-right, enter from y+18 scale 0.94 with overshoot; 3.5 s countdown line along the bottom edge; exit slides right + fade. Max 3 stacked.
- **Number changes** (free space, reclaimable totals, health score): count up/down over 0.7–1.1 s easeOutCubic; free-space label tints success green while animating.
- **Terminal drawer**: height 0↔210 with 0.42 s ease; new lines slide in from x−6; blinking block cursor.

## Screens

Sidebar groups: **Overview** (Status) · **Maintain** (Clean, Uninstall, Optimize, Purge, Installers) · **Inspect** (Analyze). Each item shows a right-aligned badge: live size for Clean (after scan), Purge and Installers; app count for Uninstall; otherwise ⌘n hint. Bottom of sidebar: "Macintosh HD" usage bar + free space.

### 1. Status (`mo status`)
12-column card grid that reflows to 6/12 at narrow widths. Cards: Health ring (score, label, uptime, three clickable suggestions linking to Clean/Optimize/Purge) · CPU (live dot, 12 per-core vertical bars P/E colored with spring height, 48-sample sparkline) · Memory (stacked bar App/Wired/Compressed + Swap) · Disk (free, usage bar, read/write, link to Analyze) · Network (down/up sparklines) · Top processes (rows physically reorder by CPU with spring) · Battery (shimmering charge bar, capacity, cycles, temperature). Cards lift 2 px on hover with a cursor-following radial glow.

### 2. Clean (`mo clean`)
States: **idle → scanning → results → cleaning → done/empty**.
- Idle: 300 px segmented ring (tick marks) showing free space, breathing halo, headline "Dig out the junk", Scan button with ripples.
- Scanning: rotating comet glow behind the ring plus an orbiting white dot; ring fills with progress; live found size in center; current path in mono below; category chips pop in as each category completes; Stop button.
- Results: left column ring segmented by category color, proportional to *selected* size, sweeping in on appear; "Found" and "Free after cleaning". Right: category list with tri-state checkboxes, color dot, name, description, `selected / total`, chevron; rows expand (height animation) to per-path items with their own checkboxes. Footer: Dry-run toggle, "n of m locations", primary "Clean 48.2 GB" / "Preview 48.2 GB".
- Cleaning: ring fills green, freed counter climbs, path ticker.
- Done: ring sweeps full, check mark draws itself, particle burst (≈34 particles radiating from the ring), toast. Dry-run done offers "Back to results".

### 3. Uninstall (`mo uninstall`)
Two columns. Left: search field (accent focus ring), segmented sort Largest / Name / Least used with a sliding pill, app list (icon from bundle, name, "Opened …", total size). Right: big icon, name, version, last opened, "will be removed" total; a card listing the app bundle (always checked) plus every leftover with a kind tag (Cache, Prefs, Container, Launch item, Logs, State, Support) colored per kind and individual checkboxes. Red "Uninstall X" button. During removal each row is struck through, dims and shifts right in sequence; the icon then shrinks and flies toward the bottom-left (toward the Dock Trash); the list row collapses; toast.

### 4. Optimize (`mo optimize`)
Header card with "n of m tasks selected", estimated time, live percentage and "Run tasks". Thin progress bar. Task list: toggle, name, `admin` badge where needed, description, the exact shell command in mono. Running row: tinted background, shimmer sweep, 2 px accent edge, spinner. Finished row: popping check + duration. Tasks list comes from what `mo optimize` actually performs; let the user disable individual ones only if the CLI supports it, otherwise show them read-only.

### 5. Purge (`mo purge`) and 6. Installers (`mo installer`)
Shared list layout: big mono "Reclaimable" total that counts down, explanatory note, Select all / None. Rows: checkbox, tag chip (`node_modules`, `target`, `.venv`, `dmg`, `pkg`, `iso`…), path, modified/downloaded date, size. Purge marks projects touched in the last 7 days as `recent` and leaves them unchecked by default. Running: rows fly out to the right and collapse one by one; footer shows "k of n removed" with a shimmering bar; success banner pops in.

### 7. Analyze (`mo analyze <path>`)
Breadcrumb bar with back button and total size. Left: squarified treemap of the current folder (category palette, label + size when the tile is large enough, hover brighten). Clicking a folder zooms *into that tile* (scale from the tile's center); going up zooms out. Moving an item to Trash makes the remaining tiles animate into the freed space. Right: sorted list with color dot, size, relative bar, open-folder and trash buttons. Scan lazily per level, cache results, and show a skeleton while scanning.

### Global
- **Terminal drawer** (⌘J): header "TERMINAL · zsh · ~/", clear and close; color-coded lines; auto-scroll.
- **Header**: title + subtitle, copyable command pill (turns green "copied ✓"), terminal toggle.
- **Toasts** for every completed action with the freed size.
- **Menu bar extra** (optional, phase 2): free space + "Quick clean (dry run)".

## Deliverables

1. Xcode project `Digby` with the structure above, building with zero warnings.
2. `README.md`: requirements, how to install `mo`, how the app calls it, a security note.
3. `NOTES.md`: each CLI command and flag the app relies on, verified against the repo, plus any design deviations and why.
4. Screenshots of all 7 screens compared side-by-side with the design reference.

Build order: MoleRunner + Terminal → Clean (full flow, dry-run first) → Status → Uninstall → Analyze → Optimize → Purge/Installers → polish motion → tests.
