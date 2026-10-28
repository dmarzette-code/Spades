import SwiftUI
import SpadesEngine

@main
struct SpadesApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}
