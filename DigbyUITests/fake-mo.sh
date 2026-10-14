#!/bin/bash
# Fake `mo` for Digby's UI tests. Replays shortened Mole 1.59 output for `mo clean`
# and never touches real files: the paths it prints do not exist, and everything it
# writes goes into $FAKE_MO_DIR (the folder the test passes as -moleConfigDir).
# Unchecked rows that Digby excludes via the whitelist are reported as skipped and left
# out of the totals, so the UI shows whether exclusions reached Mole.
#
# FAKE_MO_DELAY  seconds between output lines (default 0.02)
# FAKE_MO_EMPTY  when 1, the scan finds nothing

DIR="${FAKE_MO_DIR:?FAKE_MO_DIR must be set}"
mkdir -p "$DIR"
DELAY="${FAKE_MO_DELAY:-0.02}"

case "$1" in
  --version)
    printf 'Mole version 1.59.1\nmacOS: 15.0\nArchitecture: arm64\n'
    exit 0 ;;
  clean) ;;
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

# section|path|size|bytes
ROWS=(
  "User essentials|/Users/test/Library/Caches/Google|800.0MB|800000000"
  "User essentials|/Users/test/Library/Caches/Homebrew|400.0MB|400000000"
  "User essentials|/Users/test/Library/Logs/DiagnosticReports|172KB|172000"
  "Browsers|/Users/test/Library/Caches/com.google.Chrome|640.0MB|640000000"
)

TOTAL=0
ITEMS=0
LIST="# Mole Cleanup Preview (fake)"$'\n'
CURRENT=""
for row in "${ROWS[@]}"; do
  IFS='|' read -r section path size bytes <<< "$row"
  if [[ "$section" != "$CURRENT" ]]; then
    say "➤ $section"
    LIST+=$'\n'"=== $section ==="$'\n'
    CURRENT="$section"
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

say "➤ Developer tools"
say "  $GLYPH npm cache · would clean"
say "  $GLYPH npm cache directory · 3 items, 465.5MB$SUFFIX"
TOTAL=$((TOTAL + 465500000))
ITEMS=$((ITEMS + 1))

[[ $DRY == 1 ]] && printf '%s' "$LIST" > "$DIR/clean-list.txt"

HUMAN=$(awk -v b="$TOTAL" 'BEGIN { printf "%.2fGB", b / 1e9 }')
say "======================================================================"
if [[ $DRY == 1 ]]; then
  say "Dry run complete - no changes made"
  say "Potential space: $HUMAN | Items: $ITEMS | Categories: 3"
else
  say "Cleanup complete"
  say "Tracked cleanup: $HUMAN | Items cleaned: $ITEMS | Categories: 3"
fi
exit 0
