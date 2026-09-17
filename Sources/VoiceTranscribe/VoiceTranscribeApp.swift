import SwiftUI

enum AppWindowMetrics {
    static let mainMinWidth: CGFloat = 1240
    static let mainMinHeight: CGFloat = 720
    static let settingsWidth: CGFloat = 960
    static let settingsHeight: CGFloat = 680
}

@main
struct VoiceTranscribeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: AppWindowMetrics.mainMinWidth, minHeight: AppWindowMetrics.mainMinHeight)
        }
        .defaultSize(width: AppWindowMetrics.mainMinWidth, height: AppWindowMetrics.mainMinHeight)
        Settings {
            SettingsView()
                .environmentObject(appModel)
                .frame(width: AppWindowMetrics.settingsWidth, height: AppWindowMetrics.settingsHeight)
        }
    }
}
