import SwiftUI

@main
struct TalkieApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.name.isEmpty {
                    WelcomeView(model: model)
                } else {
                    BoardScreen(model: model)
                }
            }
            .onAppear { model.start() }
            .onChange(of: phase) { _, new in
                switch new {
                case .background: model.enteredBackground()
                case .active: model.becameActive()
                default: break
                }
            }
            // The hardware is light grey in every theme, like the Mac app.
            .preferredColorScheme(.light)
        }
    }
}
