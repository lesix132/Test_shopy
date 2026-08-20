import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query private var offers: [JobOffer]

    @State private var viewModel: SettingsViewModel?
    @State private var showingDeleteConfirm = false
    @State private var exportURL: URL?
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Réglages")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(secretStore: services.keychain, claude: services.claude)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        #endif
    }

    @ViewBuilder
    private func content(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Form {
            apiSection(vm)
            dataSection(vm)
            aboutSection
            if let message = vm.statusMessage {
                Section {
                    Label(message, systemImage: vm.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(vm.isError ? .orange : .green)
                }
            }
        }
    }

    @ViewBuilder
    private func apiSection(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Section {
            HStack {
                Image(systemName: vm.hasStoredKey ? "key.fill" : "key")
                    .foregroundStyle(vm.hasStoredKey ? .green : .secondary)
                Text(vm.hasStoredKey ? "Clé enregistrée (Keychain)" : "Aucune clé enregistrée")
                    .font(.subheadline)
            }
            SecureField("Clé API Anthropic (sk-ant-…)", text: $vm.apiKeyInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            Button("Enregistrer la clé") { vm.saveKey() }
                .disabled(vm.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button {
                Task { await vm.testKey() }
            } label: {
                if vm.isTesting {
                    HStack { ProgressView(); Text("Test…") }
                } else {
                    Text("Tester la clé")
                }
            }
            .disabled(!vm.hasStoredKey || vm.isTesting)
            if vm.hasStoredKey {
                Button("Supprimer la clé", role: .destructive) { vm.deleteKey() }
            }
        } header: {
            Text("Clé API")
        } footer: {
            Text("La clé est stockée de façon sécurisée dans le Keychain, jamais en clair. Obtenez-en une sur console.anthropic.com. Modèle utilisé : \(AppConfig.claudeModel).")
        }
    }

    @ViewBuilder
    private func dataSection(_ vm: SettingsViewModel) -> some View {
        Section("Données") {
            LabeledContent("Offres enregistrées", value: "\(offers.count)")
            Button {
                if let url = vm.exportData(offers: offers) {
                    exportURL = url
                    #if os(iOS)
                    showingShare = true
                    #elseif os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    #endif
                }
            } label: {
                Label("Exporter (JSON)", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Supprimer toutes les données", systemImage: "trash")
            }
            .confirmationDialog(
                "Supprimer toutes les offres, CV et lettres ?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Tout supprimer", role: .destructive) {
                    vm.deleteAllData(context: modelContext)
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private var aboutSection: some View {
        Section("À propos") {
            LabeledContent("Version", value: Bundle.main.appVersion)
            Text("JobTrack n'automatise jamais la lecture de LinkedIn. Importez vos offres manuellement (partage, collage, ou capture d'écran).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#if os(macOS)
import AppKit
#endif
