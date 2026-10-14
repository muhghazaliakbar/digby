#!/bin/bash
# Fake `mo` for Digby's UI tests. Replays shortened Mole 1.59 output for `mo clean`
# and never touches real files: the paths it prints do not exist, and everything it
# writes goes into $FAKE_MO_DIR (the folder the test passes as -moleConfigDir).
# Unchecked rows that Digby excludes via the whitelist are reported as skipped and left
# out of the totals, so the UI shows whether exclusions reached Mole.
#
# FAKE_MO_DELAY  seconds between output lines (default 0.02)
# FAKE_MO_EMPTY  when 1, the scan finds nothing
# FAKE_MO_DEMO   when 1, prints larger demo data (used for the README screenshots)
#                and also answers status, analyze and uninstall --list

DIR="${FAKE_MO_DIR:?FAKE_MO_DIR must be set}"
mkdir -p "$DIR"
DELAY="${FAKE_MO_DELAY:-0.02}"

case "$1" in
  --version)
    printf 'Mole version 1.59.1\nmacOS: 15.0\nArchitecture: arm64\n'
    exit 0 ;;
  clean) ;;
  status|analyze|uninstall)
    if [[ "$FAKE_MO_DEMO" == "1" ]]; then
      exec "$(dirname "$0")/demo-mo.sh" "$@"
    fi
    exit 0 ;;
  *) exit 0 ;;
esac

DRY=0
[[ "$2" == "--dry-run" ]] && DRY=1

excluded() { [[ -f "$DIR/whitelist" ]] && grep -qxF "$1" "$DIR/whitelist"; }
say() { echo "$1"; sleep "$DELAY"; }

say "Clean Your Mac"
[[ $DRY == 1 ]] && say "Dry Run Mode, Preview only, no deletions"
say "✓ Whitelist: 1 core patterns active"
say "  ↳ /Users/test/.gradle/caches/*"

if [[ "$FAKE_MO_EMPTY" == "1" ]]; then
  for section in "User essentials" "Browsers" "Developer tools"; do
    say "➤ $section"
    say "  ✓ Nothing to clean"
  done
  say "======================================================================"
  say "Potential space: 0B | Items: 0 | Categories: 0"
  exit 0
fi

GLYPH="→"; SUFFIX=" dry"
[[ $DRY == 0 ]] && GLYPH="✓" && SUFFIX=""

human() { awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.2fGB", b / 1e9; else if (b >= 1e6) printf "%.1fMB", b / 1e6; else printf "%dKB", b / 1e3 }'; }

# section|path|bytes
ROWS=(
  "User essentials|/Users/test/Library/Caches/Google|800000000"
  "User essentials|/Users/test/Library/Caches/Homebrew|400000000"
  "User essentials|/Users/test/Library/Logs/DiagnosticReports|172000"
  "Browsers|/Users/test/Library/Caches/com.google.Chrome|640000000"
)
if [[ "$FAKE_MO_DEMO" == "1" ]]; then
  H="$HOME"
  ROWS=(
    "User essentials|$H/.Trash|3600000000"
    "User essentials|$H/Library/Logs/CoreSimulator|660000000"
    "User essentials|$H/Library/Logs/DiagnosticReports|210000000"
    "App caches|$H/Library/Caches/com.spotify.client|1900000000"
    "App caches|$H/Library/Caches/com.figma.Desktop|1100000000"
    "App caches|$H/Library/Caches/com.tinyspeck.slackmacgap|740000000"
    "Browsers|$H/Library/Caches/Google/Chrome|2400000000"
    "Browsers|$H/Library/Application Support/Google/Chrome/Default/Service Worker|1300000000"
    "Browsers|$H/Library/Caches/com.apple.Safari|820000000"
    "Developer tools|$H/Library/Developer/Xcode/DerivedData|8400000000"
    "Developer tools|$H/Library/Developer/Xcode/iOS DeviceSupport|4700000000"
    "Developer tools|$H/.npm/_cacache|3200000000"
    "Developer tools|$H/.gradle/caches|2100000000"
    "Developer tools|$H/Library/Caches/Homebrew|1600000000"
    "App leftovers|$H/Library/Application Support/Adobe Lightroom|1800000000"
    "App leftovers|$H/Library/Containers/com.evernote.Evernote|920000000"
    "App leftovers|$H/Library/Application Support/Zwift|480000000"
  )
fi

TOTAL=0
ITEMS=0
SECTIONS=0
LIST="# Mole Cleanup Preview (fake)"$'\n'
CURRENT=""
for row in "${ROWS[@]}"; do
  IFS='|' read -r section path bytes <<< "$row"
  size=$(human "$bytes")
  if [[ "$section" != "$CURRENT" ]]; then
    say "➤ $section"
    LIST+=$'\n'"=== $section ==="$'\n'
    CURRENT="$section"
    SECTIONS=$((SECTIONS + 1))
  fi
  if excluded "$path"; then
    say "  ◎ ${path##*/} · whitelisted"
    continue
  fi
  say "  $GLYPH ${path##*/} · 1 items, $size$SUFFIX"
  LIST+="$path  # $size"$'\n'
  TOTAL=$((TOTAL + bytes))
  ITEMS=$((ITEMS + 1))
done

if [[ "$FAKE_MO_DEMO" != "1" ]]; then
  say "➤ Developer tools"
  say "  $GLYPH npm cache · would clean"
  say "  $GLYPH npm cache directory · 3 items, 465.5MB$SUFFIX"
  TOTAL=$((TOTAL + 465500000))
  ITEMS=$((ITEMS + 1))
  SECTIONS=$((SECTIONS + 1))
fi

[[ $DRY == 1 ]] && printf '%s' "$LIST" > "$DIR/clean-list.txt"

HUMAN=$(human "$TOTAL")
say "======================================================================"
if [[ $DRY == 1 ]]; then
  say "Dry run complete - no changes made"
  say "Potential space: $HUMAN | Items: $ITEMS | Categories: $SECTIONS"
else
  say "Cleanup complete"
  say "Tracked cleanup: $HUMAN | Items cleaned: $ITEMS | Categories: 3"
fi
exit 0
