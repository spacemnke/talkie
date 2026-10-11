import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The switchboard window and the floating mic are managed by AppDelegate.
        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("Talkie").font(.headline)
                Text("Talkie's settings open from the menu bar: right-click the jack and choose Settings…")
                Text("Hold ⌥Space to talk from any app.")
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
        }
    }
}
