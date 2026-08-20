import SwiftUI
import SwiftData

struct OfferListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var offers: [JobOffer]
    @State private var viewModel = OfferListViewModel()
    @State private var showingAdd = false
    @State private var linkedInMode = false

    private var filtered: [JobOffer] { viewModel.apply(to: offers) }

    var body: some View {
        NavigationStack {
            Group {
                if offers.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Offres")
            .searchable(text: $viewModel.searchText, prompt: "Rechercher")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            linkedInMode = true
                            showingAdd = true
                        } label: {
                            Label("Depuis LinkedIn (coller / partager)", systemImage: "link")
                        }
                        Button {
                            linkedInMode = false
                            showingAdd = true
                        } label: {
                            Label("Nouvelle offre", systemImage: "plus")
                        }
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) { sortMenu }
                ToolbarItem(placement: .secondaryAction) { filterMenu }
            }
            .sheet(isPresented: $showingAdd) {
                AddOfferView(linkedInHint: linkedInMode)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if viewModel.hasActiveFilters {
                Section {
                    Button("Effacer les filtres", role: .destructive) {
                        viewModel.clearFilters()
                    }
                }
            }
            ForEach(filtered) { offer in
                NavigationLink {
                    OfferDetailView(offer: offer)
                } label: {
                    OfferRow(offer: offer)
                }
            }
            .onDelete(perform: delete)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filtered[index])
        }
        try? modelContext.save()
    }

    // MARK: - Menus

    private var sortMenu: some View {
        Menu {
            Picker("Trier", selection: $viewModel.sort) {
                ForEach(OfferSort.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label("Trier", systemImage: "arrow.up.arrow.down")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Statut", selection: $viewModel.statusFilter) {
                Text("Tous").tag(ApplicationStatus?.none)
                ForEach(ApplicationStatus.allCases) { Text($0.label).tag(Optional($0)) }
            }
            let companies = viewModel.companies(in: offers)
            if !companies.isEmpty {
                Picker("Entreprise", selection: $viewModel.companyFilter) {
                    Text("Toutes").tag(String?.none)
                    ForEach(companies, id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
            let tags = viewModel.tags(in: offers)
            if !tags.isEmpty {
                Picker("Tag", selection: $viewModel.tagFilter) {
                    Text("Tous").tag(String?.none)
                    ForEach(tags, id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
        } label: {
            Label("Filtrer", systemImage: viewModel.hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucune offre", systemImage: "briefcase")
        } description: {
            Text("Ajoutez une offre en collant son texte, une capture d'écran, ou via le bouton Partager depuis Safari / LinkedIn.")
        } actions: {
            Button("Ajouter une offre") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// One row in the offers list.
private struct OfferRow: View {
    let offer: JobOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(offer.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if offer.needsParsing {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.orange)
                        .help("À analyser")
                }
            }
            if !offer.company.isEmpty || !offer.location.isEmpty {
                Text([offer.company, offer.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                StatusBadge(status: offer.status)
                if let score = offer.matchScore {
                    Label("\(score)%", systemImage: "target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(offer.dateAdded, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !offer.tags.isEmpty {
                TagChips(tags: offer.tags)
            }
        }
        .padding(.vertical, 4)
    }
}
