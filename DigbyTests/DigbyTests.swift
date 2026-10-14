import Foundation
import Testing
@testable import Digby

// Fixtures are shortened copies of real Mole 1.59 output (paths anonymised).

struct SizeParserTests {
    @Test func parsesDecimalUnits() {
        #expect(SizeParser.bytes("1.01GB") == 1.01e9)
        #expect(SizeParser.bytes("172KB") == 172_000)
        #expect(SizeParser.bytes("835.1MB") == 835.1e6)
        #expect(SizeParser.bytes("0B") == 0)
        #expect(SizeParser.bytes("667.9MB+") == 667.9e6)
        #expect(SizeParser.bytes("no size here") == nil)
    }

    @Test func lastBytesSkipsDigitsInNames() {
        #expect(SizeParser.lastBytes("Python 3.12 cache · 3 dirs, 3.1MB dry") == 3.1e6)
    }
}

struct CleanParserTests {
    static let dryRun = """
    Clean Your Mac

    Dry Run Mode, Preview only, no deletions

    ⚙ Apple Silicon | Free space: 35.79GB
    ✓ Whitelist: 3 core patterns active
      ↳ /Users/me/Library/Caches/ms-playwright*
      ↳ /Users/me/.gradle/caches/*
      ↳ /Users/me/Library/Caches/JetBrains*

    ➤ User essentials
      → User app cache · 12 items, 1.01GB dry
      → User app logs · 12 items, 172KB dry
      ◎ Trash · skipped, grant Full Disk Access to your terminal

    ➤ Browsers
      → Chrome cache · 18.7MB dry
      → Dia Service Worker, would clean 835.1MB, 0 protected

    ➤ Cloud & Office
      ✓ Nothing to clean

    ➤ Developer tools
      → npm cache · would clean
      ⊙ Docker unused data · review with docker system df

    ======================================================================
    Dry run complete - no changes made
    Potential space: 6.24GB | Items: 408 | Categories: 6
    ======================================================================
    """

    @Test func parsesSectionsItemsWhitelistAndSummary() {
        var parser = CleanParser()
        let events = Self.dryRun.split(separator: "\n").compactMap { parser.feed(String($0)) }
        #expect(events.filter { if case .whitelist = $0 { true } else { false } }.count == 3)
        #expect(events.contains(.section("User essentials")))
        #expect(events.contains(.section("Cloud & Office")))
        #expect(events.contains(.item(section: "User essentials", name: "User app cache", bytes: 1.01e9)))
        #expect(events.contains(.item(section: "Browsers", name: "Dia Service Worker", bytes: 835.1e6)))
        #expect(events.contains(.summary(bytes: 6.24e9, items: 408)))
        // Skipped (◎), review-only (⊙), size-less and "Nothing to clean" rows are not cleanable items.
        let items = events.compactMap { if case .item(_, let name, _) = $0 { name } else { nil } }
        #expect(items == ["User app cache", "User app logs", "Chrome cache", "Dia Service Worker"])
    }

    @Test func parsesRealRunSummary() {
        #expect(CleanParser.summary("Tracked cleanup: 4.5GB | Items cleaned: 97 | Categories: 4") == .summary(bytes: 4.5e9, items: 97))
    }

    @Test func parsesCleanList() {
        let text = """
        # Mole Cleanup Preview
        #   /Users/*/Library/Caches/com.example.app

        === User essentials ===
        /Users/me/Library/Caches/Google  # 18.7MB
        /Users/me/Library/Logs/CoreSimulator  # 4KB

        === App caches ===
        /Users/me/Library/Caches/GeoServices/Resources  # 51.9MB, counted under /Users/me/Library/Caches/GeoServices
        /Users/me/Library/Caches/com.apple.helpd/Generated  # 23.5MB
        """
        let sections = CleanListParser.parse(text)
        #expect(sections.map(\.name) == ["User essentials", "App caches"])
        #expect(sections[0].entries == [.init(path: "/Users/me/Library/Caches/Google", bytes: 18.7e6),
                                        .init(path: "/Users/me/Library/Logs/CoreSimulator", bytes: 4000)])
        #expect(sections[1].entries.count == 1, "children 'counted under' a parent are not double counted")
    }
}

struct PurgeParserTests {
    @Test func parsesDryRunRows() {
        let item = PurgeParser.item("✓ [DRY RUN] ~/code/web-app/node_modules, 1.24GB")
        #expect(item == .init(path: "~/code/web-app/node_modules", bytes: 1.24e9))
        #expect(PurgeParser.item("✓ ~/code/rust cli/target, 3.4GB")?.path == "~/code/rust cli/target")
        #expect(PurgeParser.item("Would free approximately: 26.62GB | Items: 144") == nil)
    }
}

struct InstallerParserTests {
    @Test func parsesSelectorRows() {
        let row = "\r\u{1B}[2K  ○ Brave-Browser.dmg                         358.3MB | Downloads "
        #expect(InstallerParser.item(ANSI.strip(row)) == .init(displayName: "Brave-Browser.dmg", bytes: 358.3e6, source: "Downloads"))
        #expect(InstallerParser.item("➤ ● Stronghold_Crusade...                      4.42GB | Downloads")?.displayName == "Stronghold_Crusade...")
        #expect(InstallerParser.item("↑↓  |  Space Select  |  Enter Confirm") == nil)
    }
}

struct OptimizeParserTests {
    @Test func parsesSectionsAndDetails() {
        #expect(OptimizeParser.event("➤ DNS & Spotlight Check") == .section("DNS & Spotlight Check"))
        #expect(OptimizeParser.event("  → DNS cache flushed") == .detail("DNS cache flushed"))
        #expect(OptimizeParser.event("Optimization Complete") == .finished)
        #expect(OptimizeParser.event("⚙ System  12/16 GB RAM") == nil)
    }
}

struct JSONPayloadTests {
    @Test func decodesStatusSnapshot() throws {
        let json = """
        {"host":"mac","uptime":"13d 11h","health_score":87,"health_score_msg":"Excellent",
         "hardware":{"cpu_model":"Apple M1 Pro","os_version":"macOS 27.0.1"},
         "cpu":{"usage":20.2,"per_core":[49.4,54.5,0,0],"p_core_count":2,"e_core_count":2},
         "memory":{"used":12366970880,"total":17179869184,"swap_used":10104143872,"pressure":""},
         "disk_io":{"read_rate":3,"write_rate":1},
         "network":[{"name":"en0","rx_rate_mbs":0.5,"tx_rate_mbs":0.1,"ip":"10.0.0.2"},{"name":"utun0","rx_rate_mbs":9,"tx_rate_mbs":9,"ip":""}],
         "batteries":[{"percent":83,"status":"discharging","cycle_count":282,"capacity":83}],
         "top_processes":[{"pid":629,"name":"WindowServer","cpu":55.6,"memory_bytes":116260864}]}
        """
        let snap = try #require(StatusSnapshot.decode(Data(json.utf8)))
        #expect(snap.health_score == 87)
        #expect(snap.cpu?.e_core_count == 2)
        #expect(snap.batteries?.first?.cycle_count == 282)
        #expect(snap.top_processes?.first?.name == "WindowServer")
        #expect(snap.networkRates.down == 0.5, "tunnel interfaces are not double counted")
    }

    @Test func decodesAnalyzeReport() throws {
        let json = """
        {"scan_status":"complete","path":"/Users/me/Downloads","overview":false,
         "entries":[{"scan_status":"complete","name":"a.dmg","path":"/Users/me/Downloads/a.dmg","size":4424902056,"is_dir":false},
                    {"name":"proj","path":"/Users/me/Downloads/proj","size":3390874765,"is_dir":true}],
         "total_size":7815776821}
        """
        let report = try #require(AnalyzeReport.decode(Data(json.utf8)))
        #expect(report.entries?.count == 2)
        #expect(report.entries?.last?.is_dir == true)
    }

    @Test func decodesAppListSkippingBadRows() {
        let json = """
        [
          {"name": "VLC", "bundle_id": "org.videolan.vlc", "source": "App", "uninstall_name": "VLC", "path": "/Applications/VLC.app", "size": "--"},
          {"name": "Broken "quote", "path": "/Applications/X.app"},
          {"name": "Zed", "bundle_id": "dev.zed.Zed", "source": "Homebrew", "uninstall_name": "zed", "path": "/Applications/Zed.app", "size": "--"}
        ]
        """
        let apps = ListedApp.decodeList(Data(json.utf8))
        #expect(apps.map(\.name) == ["VLC", "Zed"])
    }
}

struct WhitelistGuardTests {
    @Test func keepsDefaultsWhenUserHasNoFile() {
        let text = WhitelistGuard.contents(original: nil, defaults: ["/Users/me/.gradle/caches/*"], exclusions: ["/Users/me/Library/Caches/Google"])
        #expect(text.contains("/Users/me/.gradle/caches/*"))
        #expect(text.contains(WhitelistGuard.beginMarker + "\n/Users/me/Library/Caches/Google\n" + WhitelistGuard.endMarker))
    }

    @Test func preservesExistingFileAndRejectsUnsafePaths() {
        let text = WhitelistGuard.contents(original: "/custom/path\n", defaults: ["/ignored"], exclusions: ["relative/path", "/a/../b", "/ok/path"])
        #expect(text.hasPrefix("/custom/path\n"))
        #expect(!text.contains("/ignored"))
        #expect(!text.contains("relative/path"))
        #expect(!text.contains("/a/../b"))
        #expect(text.contains("/ok/path"))
    }
}

struct FormatTests {
    @Test func formatsLikeTheDesign() {
        #expect(Fmt.size(0) == "0 KB")
        #expect(Fmt.size(48_200_000_000) == "48.2 GB")
        #expect(Fmt.size(412_000_000_000) == "412 GB")
        #expect(Fmt.size(835_100_000) == "835 MB")
        #expect(Fmt.size(400) == "1 KB")
        #expect(Fmt.rate(0.5) == "512 KB/s")
    }

    @Test func treemapFillsTheRect() {
        let tiles = Treemap.layout([("a", 6.0), ("b", 6), ("c", 4), ("d", 3), ("e", 2), ("f", 2), ("g", 1)], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(tiles.count == 7)
        let area = tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        #expect(abs(area - 240_000) < 1)
    }
}
