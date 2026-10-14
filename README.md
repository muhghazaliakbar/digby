# Digby

A native macOS GUI (SwiftUI) for the open-source [Mole](https://github.com/tw93/mole) CLI (`mo`).

> Digby is an independent GUI for the open-source Mole CLI by tw93. Not affiliated with Mole or mole.fit.

Seven modules, each mapped to a `mo` command: **Status**, **Clean**, **Uninstall**, **Optimize**, **Purge**, **Installers** and **Analyze**. Every screen shows its equivalent command in the header (click to copy), and every action streams the raw CLI output into the Terminal drawer (⌘J).

## Requirements

- macOS 14 or later, Apple Silicon or Intel
- Xcode 16 or later to build
- Mole 1.59 or later (`mo status --watch`, `mo analyze --json` and `mo uninstall --list` are used)

## Install Mole

```bash
brew install mole
```

Without Homebrew, use the install script from the Mole README. If `mo` is not found, Digby shows a first-run screen with both commands and a **Locate binary…** picker.

## Build and run

```bash
open Digby.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project Digby.xcodeproj -scheme Digby -configuration Release build
```

Run the tests (parser unit tests plus UI tests for the Clean flow):

```bash
xcodebuild -project Digby.xcodeproj -scheme Digby test
```

The UI tests (Clean flow and the menu bar's Quick clean) drive the app against `DigbyUITests/fake-mo.sh`, which replays real Mole output, so they run in seconds and never scan or remove anything. The first run asks macOS to allow UI automation.

Launch arguments that mirror the design reference's props: `-startView status|clean|uninstall|optimize|purge|installers|analyze` and `-showTerminal YES`. For testing, `-moBinaryPath <path>` picks the `mo` binary and `-moleConfigDir <path>` redirects Mole's config folder.

## Menu bar

Digby also lives in the menu bar: the status item shows free space, and its panel offers **Quick clean (dry run)**, which runs `mo clean --dry-run` and opens the results in the Clean review with one click. Hide it, or hide the free-space text, from the **View** menu (*Show in Menu Bar*, *Show Free Space in Menu Bar*).

## Keyboard

| Keys | Action |
|---|---|
| ⌘1 – ⌘7 | Switch modules |
| ⌘J | Toggle the Terminal drawer |
| ⌘R | Rescan the current module |
| Esc | Cancel the running job (SIGINT) |

## How Digby calls Mole

Digby never reimplements Mole's cleaning logic. `MoleRunner` launches the `mo` binary with `Process`, streams stdout/stderr line by line (ANSI stripped), and sends SIGINT on cancel. Each command's output is parsed by a small, unit-tested parser in `Digby/Core/Parsers.swift`. See [NOTES.md](NOTES.md) for every command and flag used, and where Digby fills gaps the CLI does not cover.

## Security notes

- Every destructive action is preceded by a scan and a review screen. Nothing is removed without clicking a button that states the size.
- Clean has a first-class **Dry run** toggle mapped to `mo clean --dry-run`.
- Uninstall, Purge, Installers and Analyze move items to the **Trash** (recoverable), never `rm`.
- Admin tasks are elevated by Mole itself, which shows the macOS password dialog when it needs `sudo`. Digby never sees or stores the password.
- Digby is not sandboxed, because it must run `mo` and read the folders Mole scans.

## Project layout

```
Digby/
  App/         App entry, window chrome, sidebar, header, terminal, theme tokens
  Core/        MoleRunner, parsers, terminal log, disk info, Trash and whitelist helpers
  Components/  Rings, cards, controls, Core Animation loop effects
  Features/    One model + view per module
  Resources/   Familjen Grotesk and JetBrains Mono (SIL OFL)
DigbyTests/    Parser and helper tests (Swift Testing)
DigbyUITests/  Clean flow and menu bar UI tests, and the fake mo they run against
digby-handoff/ Design brief and interactive HTML reference
```

## License and credits

Fonts: Familjen Grotesk and JetBrains Mono, both under the SIL Open Font License (licenses in `Digby/Resources/Fonts`). Mole is © tw93 and contributors under its own license.
