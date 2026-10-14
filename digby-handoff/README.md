# Digby

Native macOS GUI for the open-source [Mole](https://github.com/tw93/mole) CLI (`mo`).
Digby is an independent project and is not affiliated with Mole or mole.fit.

## What's in this repo (so far)

- `PROMPT.md`: the build brief for a coding agent (Claude Code, Cursor…): architecture, design tokens, motion spec and every screen.
- `design/Digby.html`: interactive design reference. Single self-contained file, works offline. Open it in a browser and click through all 7 modules. ⌘1–⌘7 switch modules, ⌘J opens the terminal drawer.

## Start building

1. Install the CLI: `brew install mole`
2. Open your coding agent at the repo root and give it:
   > Read PROMPT.md and open design/Digby.html in a browser. Build the app exactly as specified, following the build order at the end of PROMPT.md.
3. The agent creates the Xcode project `Digby/` next to these files.

## Notes

- The data in the design reference is simulated. Real data comes from `mo`.
- Fonts: Familjen Grotesk and JetBrains Mono (both SIL Open Font License), to be bundled in the app.
