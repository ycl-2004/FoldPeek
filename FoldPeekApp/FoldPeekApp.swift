import SwiftUI

@main
struct FoldPeekApp: App {
    var body: some Scene {
        WindowGroup {
            WelcomeView()
        }
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentMinSize)
    }
}
