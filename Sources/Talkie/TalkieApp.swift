import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The switchboard window and the floating mic are managed by AppDelegate.
        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("Talkie").font(.headline)
                Text("Hold ⌥Space to talk from any app.")
                Text("Space talks and F changes the effect while the switchboard is in front.")
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
        }
    }
}
