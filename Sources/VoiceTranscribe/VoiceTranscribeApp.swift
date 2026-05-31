import SwiftUI

@main
struct VoiceTranscribeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 980, minHeight: 660)
        }
        Settings {
            SettingsView()
                .environmentObject(appModel)
                .frame(width: 520)
        }
    }
}
