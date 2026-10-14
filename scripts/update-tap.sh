#!/bin/bash
# Commits the cask for a release to the Homebrew tap. Needs GH_TOKEN with push access to the tap.
#
#   GH_TOKEN=... scripts/update-tap.sh 0.1.2
set -euo pipefail

version=${1:?usage: update-tap.sh <version>}
: "${GH_TOKEN:?set GH_TOKEN to a token that can push to the tap}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tap=${HOMEBREW_TAP:-muhghazaliakbar/homebrew-tap}
work=$(mktemp -d)

git clone --depth 1 "https://x-access-token:$GH_TOKEN@github.com/$tap.git" "$work"
mkdir -p "$work/Casks"
dmg="$root/dist/Digby-$version.dmg"
if [[ -f "$dmg" ]]; then
  "$root/scripts/cask.sh" "$version" "$dmg" > "$work/Casks/digby.rb"
else
  "$root/scripts/cask.sh" "$version" > "$work/Casks/digby.rb"
fi

cd "$work"
git add Casks/digby.rb
if git diff --cached --quiet; then
  echo "Cask already up to date"
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "digby $version"
git push
