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
    @State private var tab = RootView.initialTab

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack") }
                .tag(0)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(Theme.indigo)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.speech.refreshVoices() }
        }
    }
}

extension RootView {
    /// DEBUG simulator only: `-uiTab N` opens on tab N (for UI screenshots).
    static var initialTab: Int {
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.integer(forKey: "uiTab")
        #else
        0
        #endif
    }
}

#Preview {
    RootView().environment(AppEnvironment.preview())
}
