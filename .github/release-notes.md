**Digby {{VERSION}}**, a native macOS app for the open-source [Mole](https://github.com/tw93/mole) CLI.

## Install

1. Install Mole 1.59 or later: `brew install mole`
2. Download **Digby-{{VERSION}}.dmg** below, open it, and drag **Digby** into **Applications**.
<!-- unsigned -->
3. First launch: Digby is not notarized yet, so macOS blocks it once. Open Digby, close the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Digby.app
   ```
<!-- /unsigned -->

Universal app for Apple Silicon and Intel, macOS 14 Sonoma or later.

Digby is an independent GUI for the open-source Mole CLI by tw93. It is not affiliated with Mole or mole.fit.
