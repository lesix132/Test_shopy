import SwiftUI
import SwiftData
import AuthenticationServices
import UniformTypeIdentifiers

/// The "Profil" screen: the memory the AI reuses, plus geographic preferences
/// (zone, France-only, preferred regions) that filter the feed.
struct ProfileView: View {
    @Environment(AppServices.self) private var services
    @Query private var resumes: [Resume]
    @State private var viewModel = ProfileViewModel()
    @State private var connectingGoogle = false
    @State private var importingCV = false
    @State private var showFileImporter = false

    private var savedResumeText: String? {
        let text = (resumes.first(where: { $0.isDefault }) ?? resumes.first)?.extractedText
        return (text?.isEmpty == false) ? text : nil
    }

    var body: some View {
        Form {
            connectSection
            importCVSection
            identitySection
            locationSection
            searchSection

            Section {
                Button {
                    viewModel.save()
                } label: {
                    Label("Enregistrer le profil", systemImage: "square.and.arrow.down")
                }
            } footer: {
                if let message = viewModel.savedMessage {
                    Text(message).foregroundStyle(.green)
                } else {
                    Text("Ces informations restent sur ton appareil et servent à "
                         + "personnaliser automatiquement tes candidatures.")
                }
            }
        }
        .navigationTitle("Profil")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importFromPDF(url)
            }
        }
    }

    // MARK: Import CV

    @ViewBuilder
    private var importCVSection: some View {
        Section {
            if let savedResumeText {
                Button {
                    Task { await extractAndApply(savedResumeText) }
                } label: {
                    importLabel("Pré-remplir depuis mon CV enregistré", "doc.text.magnifyingglass")
                }
                .disabled(importingCV)
            }
            Button {
                showFileImporter = true
            } label: {
                importLabel("Importer un CV (PDF)…", "square.and.arrow.down")
            }
            .disabled(importingCV)
        } header: {
            Text("Importer depuis mon CV")
        } footer: {
            Text("L'IA lit ton CV et pré-remplit ton profil (nom, email, titre…). "
                 + "Tu complètes ensuite. Nécessite ta clé API.")
        }
    }

    @ViewBuilder
    private func importLabel(_ title: String, _ icon: String) -> some View {
        if importingCV {
            HStack { ProgressView(); Text("Lecture du CV…") }
        } else {
            Label(title, systemImage: icon)
        }
    }

    private func importFromPDF(_ url: URL) {
        Task {
            importingCV = true
            defer { importingCV = false }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                viewModel.savedMessage = "Impossible de lire le fichier."
                return
            }
            await extractAndApply(PDFService.extractText(from: data))
        }
    }

    private func extractAndApply(_ text: String) async {
        importingCV = true
        defer { importingCV = false }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 else {
            viewModel.savedMessage = "CV vide ou non lisible (PDF scanné ?)."
            return
        }
        do {
            let extracted = try await services.claude.extractProfile(
                resumeText: String(text.prefix(6000)))
            viewModel.applyExtracted(extracted)
        } catch let error as ClaudeError {
            viewModel.savedMessage = error.errorDescription
        } catch {
            viewModel.savedMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                viewModel.handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            #if os(iOS)
            .listRowInsets(EdgeInsets())
            #endif

            Button {
                Task {
                    connectingGoogle = true
                    defer { connectingGoogle = false }
                    try? await services.googleAuth.connect()
                    viewModel.fillEmail(services.googleAuth.connectedAddress)
                }
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text(connectingGoogle ? "Connexion…" : "Se connecter avec Google")
                }
            }
            .disabled(connectingGoogle)
        } header: {
            Text("Connexion rapide")
        } footer: {
            Text("Remplit automatiquement ton nom et ton email. "
                 + "Google réutilise la connexion Gmail.")
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        @Bindable var vm = viewModel
        Section("Identité") {
            TextField("Nom complet", text: $vm.profile.fullName)
            TextField("Titre professionnel (ex. Ingénieur nucléaire)", text: $vm.profile.headline)
            TextField("Email", text: $vm.profile.email)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
            TextField("Téléphone", text: $vm.profile.phone)
                #if os(iOS)
                .keyboardType(.phonePad)
                #endif
            TextField("LinkedIn (URL)", text: $vm.profile.linkedIn)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        @Bindable var vm = viewModel
        Section {
            TextField("Ville", text: $vm.profile.city)
            Picker("Ma région", selection: $vm.profile.regionRaw) {
                Text("Non précisée").tag("")
                ForEach(FrenchRegion.allCases) { region in
                    Text(region.rawValue).tag(region.rawValue)
                }
            }
            Toggle("Offres en France uniquement", isOn: $vm.profile.franceOnly)
        } header: {
            Text("Zone géographique")
        } footer: {
            Text("Utilisée pour filtrer et prioriser le fil d'offres.")
        }

        Section("Régions ciblées (fil)") {
            ForEach(FrenchRegion.allCases) { region in
                Button {
                    viewModel.togglePreferred(region)
                } label: {
                    HStack {
                        Text(region.rawValue)
                            .foregroundStyle(.primary)
                        Spacer()
                        if viewModel.isPreferred(region) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        @Bindable var vm = viewModel
        Section("Recherche") {
            TextField("Mots-clés (ex. nucléaire, sûreté)", text: $vm.profile.targetKeywords)
                .autocorrectionDisabled()
            // A vertical TextField (not TextEditor) so it doesn't capture the
            // scroll wheel and block the form from scrolling on macOS.
            TextField("Points forts / accroche", text: $vm.profile.summary, axis: .vertical)
                .lineLimit(3...8)
        }
    }
}
