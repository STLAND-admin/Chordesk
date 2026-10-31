import SwiftUI

@main
struct iPhoneDuoDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().tint(.gray).task {
                if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] != "1" { EmbeddedTailnet.shared.resumeIfNeeded() }
            }
        }
    }
}
