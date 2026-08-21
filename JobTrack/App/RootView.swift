import SwiftUI
import SwiftData

/// Top-level navigation. Uses a `TabView` on iOS and a `NavigationSplitView`
/// feel via tabs; on macOS the same tabs render natively.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            OfferListView()
                .tabItem { Label("Offres", systemImage: "briefcase") }

            FeedView()
                .tabItem { Label("Fil", systemImage: "dot.radiowaves.left.and.right") }

            WebBrowserView()
                .tabItem { Label("Web", systemImage: "globe") }

            FollowUpsView()
                .tabItem { Label("Relances", systemImage: "bell.badge") }

            ResumeListView()
                .tabItem { Label("CV", systemImage: "doc.text") }

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .task { drainInbox() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { drainInbox() }
        }
    }

    /// Imports items captured by the Share Extension into SwiftData.
    /// New offers arrive with `needsParsing = true` so the UI can flag them.
    private func drainInbox() {
        let pending = ImportInbox.drain()
        guard !pending.isEmpty else { return }
        for item in pending {
            let offer = JobOffer(
                dateAdded: item.capturedAt,
                rawImportText: item.rawText,
                needsParsing: true
            )
            offer.sourceURL = item.sourceURL
            modelContext.insert(offer)
        }
        try? modelContext.save()
    }
}
