import SwiftUI

@main
struct MemoriseApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}

/// Root tab bar: Practice, Stats, Settings.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.indigo)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.speech.refreshVoices() }
        }
    }
}

#Preview {
    RootView().environment(AppEnvironment.preview())
}
