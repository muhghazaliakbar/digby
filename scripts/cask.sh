#!/bin/bash
# Prints the Homebrew cask for a Digby release.
#
#   scripts/cask.sh 0.1.2 dist/Digby-0.1.2.dmg    # checksum from a local DMG
#   scripts/cask.sh 0.1.2                         # checksum from the published release
set -euo pipefail

version=${1:?usage: cask.sh <version> [dmg]}
dmg=${2:-}
if [[ -n "$dmg" ]]; then
  sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
else
  sha=$(curl -fsSL "https://github.com/muhghazaliakbar/digby/releases/download/v$version/SHA256SUMS.txt" | awk -v f="Digby-$version.dmg" '$2 == f { print $1 }')
fi
[[ ${#sha} -eq 64 ]] || { echo "Could not determine the DMG checksum" >&2; exit 1; }

cat <<CASK
cask "digby" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/muhghazaliakbar/digby/releases/download/v#{version}/Digby-#{version}.dmg"
  name "Digby"
  desc "Native GUI for the Mole disk cleanup CLI"
  homepage "https://github.com/muhghazaliakbar/digby"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on formula: "mole"
  depends_on macos: :sonoma

  app "Digby.app"

  zap trash: [
    "~/Library/Caches/com.muhghazaliakbar.digby",
    "~/Library/HTTPStorages/com.muhghazaliakbar.digby",
    "~/Library/Preferences/com.muhghazaliakbar.digby.plist",
    "~/Library/Saved Application State/com.muhghazaliakbar.digby.savedState",
  ]

  caveats <<~EOS
    This build is not notarized yet. The first time you open Digby, macOS blocks it:
    open System Settings → Privacy & Security and click "Open Anyway".
  EOS
end
CASK
