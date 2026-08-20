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
                Section {
                    ForEach(viewModel.sources) { source in
                        Toggle(isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in viewModel.toggle(source) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(source.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.map { viewModel.sources[$0] }.forEach(viewModel.remove)
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("Sources publiques d'offres (RSS/JSON). N'ajoute pas de "
                         + "contenu nécessitant une connexion à un compte.")
                }

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
}
