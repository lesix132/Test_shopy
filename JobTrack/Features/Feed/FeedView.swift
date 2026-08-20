import SwiftUI
import SwiftData

/// The "Fil" tab: a refreshing feed of job postings from public, legitimate
/// sources (RSS/JSON job boards). Never LinkedIn's personal feed. Each item can
/// be saved into the user's JobOffer pipeline in one tap.
struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    /// Existing offers, used to mark feed items already saved (by source URL).
    @Query private var offers: [JobOffer]

    @State private var viewModel: FeedViewModel?
    @State private var showingSources = false

    private var savedURLs: Set<String> {
        Set(offers.compactMap { $0.sourceURL })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Fil")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSources = true
                    } label: {
                        Label("Sources", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSources) {
                if let viewModel {
                    FeedSourcesView(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FeedViewModel(service: services.jobFeed)
            }
        }
        .task {
            await viewModel?.loadIfNeeded()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: FeedViewModel) -> some View {
        @Bindable var vm = vm
        List {
            legitimacyNote

            if !vm.failures.isEmpty {
                Section {
                    ForEach(vm.failures, id: \.self) { failure in
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sources indisponibles")
                }
            }

            if vm.filteredItems.isEmpty, !vm.isLoading {
                Section {
                    emptyState(vm)
                }
            } else {
                Section {
                    ForEach(vm.filteredItems) { item in
                        FeedRow(
                            item: item,
                            isSaved: item.url.map(savedURLs.contains) ?? false,
                            onSave: { save(item, using: vm) }
                        )
                    }
                } header: {
                    Text("\(vm.filteredItems.count) offre(s)")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .searchable(text: $vm.keyword, prompt: "Filtrer le fil")
        .refreshable { await vm.refresh() }
        .overlay {
            if vm.isLoading, vm.filteredItems.isEmpty {
                ProgressView("Chargement du fil…")
            }
        }
    }

    private var legitimacyNote: some View {
        Section {
            Label {
                Text("Fil alimenté par des sources publiques et légales (job boards). "
                     + "LinkedIn n'est jamais lu automatiquement — utilise le partage, "
                     + "le collage ou l'OCR pour les offres LinkedIn.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ vm: FeedViewModel) -> some View {
        if !vm.hasEnabledSource {
            ContentUnavailableView {
                Label("Aucune source active", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Active ou ajoute une source pour voir des offres.")
            } actions: {
                Button("Gérer les sources") { showingSources = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Fil vide", systemImage: "tray")
            } description: {
                Text("Aucune offre pour l'instant. Tire pour rafraîchir.")
            }
        }
    }

    // MARK: - Save

    private func save(_ item: FeedItem, using vm: FeedViewModel) {
        // Avoid duplicates by source URL.
        if let url = item.url, savedURLs.contains(url) { return }
        let offer = vm.makeOffer(from: item)
        modelContext.insert(offer)
        try? modelContext.save()
    }
}

// MARK: - Row

private struct FeedRow: View {
    let item: FeedItem
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? "Offre" : item.title)
                .font(.headline)

            HStack(spacing: 6) {
                if !item.company.isEmpty {
                    Text(item.company).fontWeight(.medium)
                }
                if !item.location.isEmpty {
                    Text("· \(item.location)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack {
                Label(item.sourceName, systemImage: "dot.radiowaves.left.and.right")
                if let date = item.publishedAt {
                    Text("· \(date.formatted(.relative(presentation: .named)))")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                if let urlString = item.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Ouvrir", systemImage: "safari")
                    }
                    .font(.callout)
                }
                Spacer()
                Button(action: onSave) {
                    if isSaved {
                        Label("Enregistrée", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Enregistrer", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.callout)
                .buttonStyle(.borderless)
                .disabled(isSaved)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
