# Notes

Verified against Mole **1.59.1** (`tw93/mole` main, October 2026). Where the brief and the CLI disagreed, the CLI won; each case is listed below.

## Commands and flags Digby relies on

| Module | Command | Output used |
|---|---|---|
| Startup | `mo --version` | Version, macOS and architecture lines |
| Status | `mo status --watch --interval 1s` | NDJSON snapshots, one per second (CPU per core, network, disk I/O) |
| Status | `mo status --json` (every 4 s) | Full snapshot: health score, hardware, processes, battery, thermal. Watch snapshots omit some of these |
| Clean, scan | `mo clean --dry-run` | `➤ Section` headers, `→ name · N items, SIZE dry` rows, `↳` whitelist patterns, `Potential space:` summary |
| Clean, scan | `~/.config/mole/clean-list.txt` | Per-path preview written by the dry run (`=== Section ===`, `path  # SIZE`) |
| Clean, run | `mo clean` / `mo clean --dry-run` | Same format; `✓` rows, `Tracked cleanup:` summary |
| Uninstall | `mo uninstall --list` | JSON app inventory (auto-JSON when piped) |
| Optimize | `mo optimize` | `➤ Task` headers and `→` result lines per task |
| Purge | `mo purge --dry-run` | `✓ [DRY RUN] path, SIZE` rows |
| Installers | `mo installer --dry-run` | Selector rows `○ name  SIZE \| Source` (stdin is `/dev/null`, so the selector exits after printing) |
| Analyze | `mo analyze --json <path>` | `entries[]` with `name`, `path`, `size`, `is_dir`, `scan_status` |

Sizes are Mole's `bytes_to_human` output, which uses decimal units (1 GB = 10⁹ bytes); Digby formats with the same base.

## Where Digby fills gaps in the CLI

- **Clean selection.** `mo clean` has no per-path selection flag (`--select` was removed). To honour unchecked rows, Digby appends them to `~/.config/mole/whitelist` for one run, then restores the file exactly (or removes it if the user had none). If the user has no whitelist, the scan's active default patterns are written first so creating the file does not drop them. A marker file lets Digby restore on the next launch if it quits mid-run. Rows without a path (for example "npm cache", cleaned by a tool command) cannot be excluded and are shown locked.
- **Uninstall.** Mole's non-interactive uninstall (`mo uninstall <name>`) asks for confirmation on stdin and has no per-file selection. The design needs per-file checkboxes, so Digby takes the app inventory from `mo uninstall --list`, finds leftovers in `~/Library` by bundle ID and name, and moves the checked items to the Trash with `NSWorkspace.recycle`. It refuses to uninstall an app that is still running.
- **Purge and Installers.** Discovery comes from Mole's dry runs. Removal of the checked rows uses the Trash instead of Mole's permanent delete (the brief prefers Trash, and neither command accepts a per-item list). Purge marks artifacts whose folder or project changed in the last 7 days as `recent` and leaves them unchecked, matching Mole's default.
- **Installers paths.** The selector truncates long names (`Stronghold_Crusade...`); Digby resolves them against the reported source folder by prefix and size.
- **Optimize.** Mole runs all catalog tasks in one pass and has no per-task flag (exclusions live in `mo optimize --whitelist`, an interactive menu). The task list mirrors `lib/optimize/catalog.sh`; toggles are shown on and read-only, and the mono line shows Mole's handler name, then the task's result once it runs. `admin` badges mark tasks that call `sudo`; Mole shows the macOS password dialog itself when no terminal is attached.
- **Memory breakdown.** `mo status --json` reports used/total/swap but not App/Wired/Compressed, so those come from `host_statistics64`.
- **Analyze trash.** Items are moved to the Trash with `NSWorkspace.recycle`, as `mo analyze` does after confirmation.

## Design deviations

- **Menu bar extra.** The reference has no mock-up for it, so the panel reuses the app's tokens and components. Quick clean shares the Clean module's state: a scan started from the menu bar shows up in the main window and the other way round.

- **App icons.** Uninstall shows each app's real icon instead of the reference's coloured letter tiles, as the brief asks ("icon from bundle").
- **Window chrome.** The real traffic lights are repositioned into the sidebar at the design's offsets instead of drawn ones.
- **Optimize toggles.** Read-only (see above). The reference's 9 sample tasks are replaced with Mole's 20 real tasks.
- **Status cards.** CPU shows Mole's real core split (efficiency cores are listed after performance cores). The battery card shows "No battery" on desktops. Temperature shows "—" when Mole cannot read the sensor.
- **Clean progress.** Mole does not report a percentage, so scan and clean progress is estimated from the sections Mole has finished.
- **Toast text.** Purge, Installers and Uninstall toasts say "to Trash" rather than "freed", because space is only reclaimed once the Trash is emptied.
- **Motion.** Looping effects (ripples, halo, comet, orbit, shimmer, spinner, live dot) run as Core Animation layers so idle CPU stays near zero; one-shot transitions use SwiftUI springs and curves with the reference's timings. Reduce Motion disables movement.

## Tests

- `DigbyTests`: parsers for every command, JSON payloads, whitelist contents, formatting, treemap layout.
- `DigbyUITests`: the menu bar extra (free space, Quick clean, Review in Digby) and the Clean flow (scan, review, unchecking, select all/none, dry-run preview, real run, stop, empty result) against `fake-mo.sh`. The XCTest runner is sandboxed and cannot read the app's files, so checks go through the UI: the fake leaves whitelisted paths out of its totals, so the sizes Digby shows prove that exclusions reached Mole and that the whitelist was restored. Each run leaves an empty folder under `/tmp/digby-ui-*`.
- On macOS, UI tests must use `click()`; `tap()` does not trigger SwiftUI buttons.

The real Clean flow was also verified end to end against Mole 1.59.1 in dry-run mode.

## Not yet done

- Side-by-side screenshots against the design reference.
