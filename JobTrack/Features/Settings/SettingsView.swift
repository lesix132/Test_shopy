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
                viewModel = SettingsViewModel(
                    secretStore: services.keychain,
                    claude: services.claude,
                    googleAuth: services.googleAuth)
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
            frenchSourcesSection(vm)
            gmailSection(vm)
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
    private func frenchSourcesSection(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Section {
            // France Travail
            HStack {
                Image(systemName: vm.hasFranceTravail ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(vm.hasFranceTravail ? .green : .secondary)
                Text("France Travail").font(.subheadline.weight(.medium))
            }
            if !vm.hasFranceTravail {
                TextField("Identifiant client", text: $vm.ftClientIDInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("Clé secrète client", text: $vm.ftClientSecretInput)
                Button("Enregistrer France Travail") { vm.saveFranceTravail() }
                    .disabled(vm.ftClientIDInput.trimmingCharacters(in: .whitespaces).isEmpty
                              || vm.ftClientSecretInput.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Supprimer les clés France Travail", role: .destructive) {
                    vm.deleteFranceTravail()
                }
            }

            Divider()

            // Adzuna
            HStack {
                Image(systemName: vm.hasAdzuna ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(vm.hasAdzuna ? .green : .secondary)
                Text("Adzuna").font(.subheadline.weight(.medium))
            }
            if !vm.hasAdzuna {
                TextField("app_id", text: $vm.adzunaAppIDInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("app_key", text: $vm.adzunaAppKeyInput)
                Button("Enregistrer Adzuna") { vm.saveAdzuna() }
                    .disabled(vm.adzunaAppIDInput.trimmingCharacters(in: .whitespaces).isEmpty
                              || vm.adzunaAppKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Supprimer les clés Adzuna", role: .destructive) {
                    vm.deleteAdzuna()
                }
            }
        } header: {
            Text("Sources France (offres FR)")
        } footer: {
            Text("Alternative légale à LinkedIn/Indeed. Clés gratuites : "
                 + "France Travail sur francetravail.io (espace développeur), "
                 + "Adzuna sur developer.adzuna.com. Une fois enregistrées, active "
                 + "la source dans l'onglet Fil → Sources, et règle les mots-clés "
                 + "(défaut : « \(AppConfig.defaultFeedQuery) »).")
        }
    }

    @ViewBuilder
    private func gmailSection(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Section {
            HStack {
                Image(systemName: vm.gmailConnected ? "envelope.circle.fill" : "envelope.circle")
                    .foregroundStyle(vm.gmailConnected ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(vm.gmailConnected ? "Gmail connecté" : "Gmail non connecté")
                        .font(.subheadline)
                    if let address = vm.gmailAddress {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !vm.hasGoogleClientID {
                TextField("Identifiant client OAuth (…apps.googleusercontent.com)",
                          text: $vm.gmailClientIDInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Enregistrer l'identifiant") { vm.saveGoogleClientID() }
                    .disabled(vm.gmailClientIDInput.trimmingCharacters(in: .whitespaces).isEmpty)
            } else if !vm.gmailConnected {
                Button {
                    Task { await vm.connectGmail() }
                } label: {
                    if vm.isConnectingGmail {
                        HStack { ProgressView(); Text("Connexion…") }
                    } else {
                        Label("Connecter Gmail", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .disabled(vm.isConnectingGmail)
                Button("Supprimer l'identifiant Google", role: .destructive) {
                    vm.deleteGoogleClientID()
                }
            } else {
                Button("Déconnecter Gmail", role: .destructive) { vm.disconnectGmail() }
            }
        } header: {
            Text("Gmail (envoi & relances automatiques)")
        } footer: {
            Text("Connecte ton compte pour envoyer les e-mails et détecter les "
                 + "réponses. Crée un identifiant OAuth (type iOS) sur "
                 + "console.cloud.google.com, active l'API Gmail, et ajoute les "
                 + "scopes gmail.send et gmail.readonly. Aucun mot de passe n'est "
                 + "stocké — seul un jeton sécurisé dans le Keychain.")
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
