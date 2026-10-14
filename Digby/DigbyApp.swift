import SwiftUI

@main
struct DigbyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}
