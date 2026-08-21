import SwiftUI
import AuthenticationServices

/// The "Profil" screen: the memory the AI reuses, plus geographic preferences
/// (zone, France-only, preferred regions) that filter the feed.
struct ProfileView: View {
    @Environment(AppServices.self) private var services
    @State private var viewModel = ProfileViewModel()
    @State private var connectingGoogle = false

    var body: some View {
        Form {
            connectSection
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
            VStack(alignment: .leading) {
                Text("Points forts / accroche").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $vm.profile.summary).frame(minHeight: 100)
            }
        }
    }
}
