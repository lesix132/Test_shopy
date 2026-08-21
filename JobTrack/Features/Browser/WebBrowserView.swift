import SwiftUI
import SwiftData

/// In-app browser: the user logs into their own email and job sites and browses
/// normally. "Importer cette offre" captures the visible text of the current
/// page (user-initiated) and turns it into a JobOffer via Claude.
struct WebBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var model = WebViewModel()
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Divider()
            ZStack(alignment: .top) {
                WebView(model: model)
                if model.isLoading {
                    ProgressView()
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 6)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Import", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: Address bar

    private var addressBar: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: model.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Adresse ou recherche", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .submitLabel(.go)
                #endif
                .autocorrectionDisabled()
                .onSubmit { model.load(model.addressText) }
            Button {
                model.reloadOrStop()
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Bottom toolbar

    private var bottomBar: some View {
        HStack {
            Button { model.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!model.canGoBack)
            Spacer()
            Button { model.goForward() } label: { Image(systemName: "chevron.forward") }
                .disabled(!model.canGoForward)
            Spacer()

            Menu {
                ForEach(WebShortcut.all) { shortcut in
                    Button {
                        model.loadURL(shortcut.url)
                    } label: {
                        Label(shortcut.name, systemImage: shortcut.systemImage)
                    }
                }
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            Spacer()

            Menu {
                Button {
                    importCurrentPage()
                } label: {
                    Label("Importer l'offre", systemImage: "square.and.arrow.down")
                }
                Button {
                    fillMyInfo()
                } label: {
                    Label("Remplir mes infos", systemImage: "person.text.rectangle")
                }
            } label: {
                if importing {
                    ProgressView()
                } else {
                    Label("Postuler", systemImage: "paperplane.fill")
                }
            }
            .disabled(importing)
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: Autofill

    private func fillMyInfo() {
        let profile = ProfileStore().load()
        Task {
            await model.autofillStandardFields(
                fullName: profile.fullName, email: profile.email, phone: profile.phone)
            importMessage = "Champs standards pré-remplis quand c'était possible. "
                + "Vérifie et complète le formulaire, puis joins ton CV."
        }
    }

    // MARK: Import

    private func importCurrentPage() {
        importing = true
        Task {
            defer { importing = false }
            guard let text = await model.captureVisibleText(), text.count > 40 else {
                importMessage = "Page vide ou trop courte pour être importée."
                return
            }
            do {
                let parsed = try await services.claude.parseOffer(rawText: String(text.prefix(8000)))
                let offer = JobOffer(
                    title: parsed.title,
                    company: parsed.company,
                    location: parsed.location,
                    descriptionText: parsed.description,
                    sourceURL: model.currentURL?.absoluteString,
                    needsParsing: false
                )
                if let region = FrenchRegion.detect(from: parsed.location) {
                    offer.tags.append(region.rawValue)
                }
                modelContext.insert(offer)
                try? modelContext.save()
                let title = parsed.title.isEmpty ? "offre" : parsed.title
                importMessage = "Importée : \(title). Retrouve-la dans l'onglet Offres."
            } catch let error as ClaudeError {
                importMessage = error.errorDescription
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }
}
