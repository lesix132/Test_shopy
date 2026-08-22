import SwiftUI

/// Manage the feed sources: toggle built-ins, add custom RSS/Atom URLs, and
/// remove or reset. Presented as a sheet from the Feed tab.
struct FeedSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: FeedViewModel

    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        NavigationStack {
            Form {
                sourcesSection(
                    for: .jobs, header: "Offres",
                    footer: "Sources publiques d'offres (RSS/JSON). N'ajoute pas de "
                        + "contenu nécessitant une connexion à un compte.")

                sourcesSection(
                    for: .news, header: "Actualités de l'emploi",
                    footer: "Flux d'actualités publics, mis à jour en continu.")

                Section("Ajouter un flux RSS") {
                    TextField("Nom (ex. Careers Acme)", text: $newName)
                    TextField("URL du flux RSS/Atom", text: $newURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    Button("Ajouter") {
                        viewModel.addRSSSource(name: newName, urlString: newURL)
                        newName = ""
                        newURL = ""
                    }
                    .disabled(URL(string: newURL.trimmingCharacters(in: .whitespaces)) == nil
                              || newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    Button("Réinitialiser les sources par défaut", role: .destructive) {
                        viewModel.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Sources du fil")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    /// One section listing the sources of a given category (jobs or news).
    @ViewBuilder
    private func sourcesSection(for category: FeedCategory,
                                header: String, footer: String) -> some View {
        let sources = viewModel.sources.filter { $0.category == category }
        if !sources.isEmpty {
            Section {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in viewModel.toggle(source) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(source.requiresCredentials
                                     ? "API — clés dans Réglages"
                                     : source.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if source.usesQuery {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Mots-clés (ex. nucléaire)", text: Binding(
                                    get: { source.query ?? "" },
                                    set: { viewModel.updateQuery(source, to: $0) }
                                ))
                                #if os(iOS)
                                .autocorrectionDisabled()
                                #endif
                            }
                            .font(.caption)
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { sources[$0] }.forEach(viewModel.remove)
                }
            } header: {
                Text(header)
            } footer: {
                Text(footer)
            }
        }
    }
}
