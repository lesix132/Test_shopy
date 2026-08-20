import SwiftUI
import SwiftData

/// The "Fil" tab: a refreshing feed of job postings from public, legitimate
/// sources (RSS/JSON job boards). Never LinkedIn's personal feed. Each item can
/// be translated to French, analyzed by Claude, and saved into the JobOffer
/// pipeline in one tap.
struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    /// Existing offers, used to mark feed items already saved (by source URL).
    @Query private var offers: [JobOffer]
    /// CVs, to score feed items against the default CV.
    @Query private var resumes: [Resume]

    @State private var viewModel: FeedViewModel?
    @State private var showingSources = false

    private var savedURLs: Set<String> {
        Set(offers.compactMap { $0.sourceURL })
    }

    private var defaultResumeText: String? {
        let cv = resumes.first(where: { $0.isDefault }) ?? resumes.first
        let text = cv?.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
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
                    Menu {
                        Button {
                            Task { await viewModel?.autoProcessAll(resumeText: defaultResumeText) }
                        } label: {
                            Label("Analyser & traduire tout", systemImage: "sparkles")
                        }
                        .disabled(viewModel?.isBatchProcessing ?? true)

                        Button {
                            showingSources = true
                        } label: {
                            Label("Sources", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        if viewModel?.isBatchProcessing == true {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
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
                viewModel = FeedViewModel(service: services.jobFeed, claude: services.claude)
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

            if let error = vm.lastAIError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !vm.failures.isEmpty {
                Section("Sources indisponibles") {
                    ForEach(vm.failures, id: \.self) { failure in
                        Label(failure, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if vm.filteredItems.isEmpty, !vm.isLoading {
                Section { emptyState(vm) }
            } else {
                Section("\(vm.filteredItems.count) offre(s)") {
                    ForEach(vm.filteredItems) { item in
                        FeedRow(
                            item: item,
                            region: vm.region(for: item),
                            translation: vm.translations[item.id],
                            analysis: vm.analyses[item.id],
                            isTranslating: vm.translating.contains(item.id),
                            isAnalyzing: vm.analyzing.contains(item.id),
                            isSaved: item.url.map(savedURLs.contains) ?? false,
                            onTranslate: { Task { await vm.translate(item) } },
                            onAnalyze: { Task { await vm.analyze(item, resumeText: defaultResumeText) } },
                            onSave: { save(item, using: vm) }
                        )
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .searchable(text: $vm.keyword, prompt: "Filtrer le fil")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { filtersMenu(vm) }
        }
        .refreshable { await vm.refresh() }
        .overlay {
            if vm.isLoading, vm.filteredItems.isEmpty {
                ProgressView("Chargement du fil…")
            }
        }
    }

    @ViewBuilder
    private func filtersMenu(_ vm: FeedViewModel) -> some View {
        @Bindable var vm = vm
        Menu {
            Toggle("France uniquement", isOn: $vm.franceOnly)
            Picker("Région", selection: $vm.regionFilter) {
                Text("Toutes les régions").tag(FrenchRegion?.none)
                ForEach(vm.availableRegions) { region in
                    Text(region.rawValue).tag(FrenchRegion?.some(region))
                }
            }
        } label: {
            Label("Filtres", systemImage: vm.regionFilter == nil && vm.franceOnly
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var legitimacyNote: some View {
        Section {
            Label {
                Text("Fil alimenté par des sources publiques et légales. "
                     + "LinkedIn et Indeed ne sont jamais lus automatiquement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.shield").foregroundStyle(.green)
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
        if let url = item.url, savedURLs.contains(url) { return }
        modelContext.insert(vm.makeOffer(from: item))
        try? modelContext.save()
    }
}

// MARK: - Row

private struct FeedRow: View {
    let item: FeedItem
    let region: FrenchRegion?
    let translation: TranslatedText?
    let analysis: FeedAnalysis?
    let isTranslating: Bool
    let isAnalyzing: Bool
    let isSaved: Bool
    let onTranslate: () -> Void
    let onAnalyze: () -> Void
    let onSave: () -> Void

    private var displayTitle: String {
        let t = translation?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t, !t.isEmpty { return t }
        return item.title.isEmpty ? "Offre" : item.title
    }

    /// Prefer the AI French summary, then a translation, then the original.
    private var displaySummary: String {
        if let s = analysis?.summaryFR, !s.isEmpty { return s }
        if let s = translation?.summary, !s.isEmpty { return s }
        return item.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(displayTitle).font(.headline)
                Spacer()
                if let score = analysis?.matchScore {
                    Text("\(score)%")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(scoreColor(score).opacity(0.18), in: Capsule())
                        .foregroundStyle(scoreColor(score))
                }
            }

            HStack(spacing: 6) {
                if !item.company.isEmpty { Text(item.company).fontWeight(.medium) }
                if !item.location.isEmpty { Text("· \(item.location)") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let region {
                Label(region.rawValue, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.14), in: Capsule())
                    .foregroundStyle(.blue)
            }

            if !displaySummary.isEmpty {
                Text(displaySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if let tags = analysis?.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
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

            actionBar
        }
        .padding(.vertical, 4)
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            if translation == nil {
                aiButton("Traduire", systemImage: "character.bubble",
                         busy: isTranslating, action: onTranslate)
            }
            if analysis == nil {
                aiButton("Analyser", systemImage: "sparkles",
                         busy: isAnalyzing, action: onAnalyze)
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                Link(destination: url) { Label("Ouvrir", systemImage: "safari") }
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

    @ViewBuilder
    private func aiButton(_ title: String, systemImage: String,
                          busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if busy {
                ProgressView()
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .disabled(busy)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...:  return .green
        case 50..<75: return .orange
        default:     return .red
        }
    }
}
