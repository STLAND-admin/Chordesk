import SwiftUI

@main
struct iPhoneDuoDemoApp: App {
    init() {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["DUO_UI_KEYBOARD_LAYOUT"] == "1" {
            // Seed a writable preference; launch arguments override UserDefaults
            // and cannot exercise persistence or an interactive settings switch.
            UserDefaults.standard.set(true, forKey: "fitDesktopAboveKeyboardV1")
        }
#endif
    }
    var body: some Scene {
        WindowGroup {
            ContentView().tint(.gray).task {
                if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] != "1" { EmbeddedTailnet.shared.resumeIfNeeded() }
            }
        }
    }
}
