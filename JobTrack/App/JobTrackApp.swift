import SwiftUI
import SwiftData

@main
struct JobTrackApp: App {

    /// Shared SwiftData container (App Group–backed).
    let modelContainer = SharedModelContainer.make()

    /// Dependency container for services shared across the app.
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(services)
                .modelContainer(modelContainer)
                .frame(minWidth: 480, minHeight: 360)
        }
        #endif
    }
}

/// App-level service container, injected via the SwiftUI environment.
/// Keeping services here (rather than instantiating in Views) keeps Views thin
/// and makes the Claude/Keychain dependencies swappable in previews/tests.
@Observable
final class AppServices {
    let keychain: SecretStore
    let claude: ClaudeService
    let jobFeed: JobFeedService

    init(
        keychain: SecretStore? = nil,
        claude: ClaudeService? = nil,
        jobFeed: JobFeedService? = nil
    ) {
        let store = keychain ?? KeychainService()
        self.keychain = store
        self.claude = claude ?? ClaudeAPIService(secretStore: store)
        self.jobFeed = jobFeed ?? JobFeedNetworkService()
    }
}
