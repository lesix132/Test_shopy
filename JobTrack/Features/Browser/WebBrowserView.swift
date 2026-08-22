import SwiftUI
import SwiftData

/// In-app browser: the user logs into their own email and job sites and browses
/// normally. "Importer cette offre" captures the visible text of the current
/// page (user-initiated) and turns it into a JobOffer via Claude.
struct WebBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query private var resumes: [Resume]

    @State private var model = WebViewModel()
    @State private var importing = false
    @State private var importMessage: String?
    @State private var matchAnalysis: PageMatchAnalysis?
    /// Result of an automatic background scan, shown as an "import?" banner.
    @State private var autoMatch: PageMatchAnalysis?
    @State private var scanning = false

    private var defaultResumeText: String? {
        let cv = resumes.first(where: { $0.isDefault }) ?? resumes.first
        let text = cv?.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Divider()
            ZStack(alignment: .top) {
                WebView(model: model)
                if model.isLoading || scanning {
                    ProgressView()
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 6)
                }
                if let autoMatch {
                    matchBanner(autoMatch)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onChange(of: model.isLoading) { _, loading in
            if !loading { autoScanIfNeeded() }
        }
        .onChange(of: model.currentURL) { _, _ in
            // Left the analysed page → drop its banner.
            autoMatch = nil
        }
        .alert("Import", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { matchAnalysis != nil },
            set: { if !$0 { matchAnalysis = nil } }
        )) {
            if let matchAnalysis {
                PageMatchView(analysis: matchAnalysis)
            }
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
        @Bindable var model = model
        return HStack {
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
                    importAndPrepare()
                } label: {
                    Label("Tout préparer (offre + brouillon)", systemImage: "wand.and.stars")
                }
                Button {
                    importCurrentPage()
                } label: {
                    Label("Importer l'offre seulement", systemImage: "square.and.arrow.down")
                }
                Button {
                    analyzePage()
                } label: {
                    Label("Analyser la correspondance", systemImage: "percent")
                }
                Button {
                    fillMyInfo()
                } label: {
                    Label("Remplir mes infos", systemImage: "person.text.rectangle")
                }
                Divider()
                Toggle(isOn: $model.autoScanEnabled) {
                    Label("Scan auto des offres", systemImage: "sparkles.rectangle.stack")
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

    // MARK: Auto-scan banner

    @ViewBuilder
    private func matchBanner(_ analysis: PageMatchAnalysis) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.green.opacity(0.15)).frame(width: 42, height: 42)
                Text("\(analysis.overallScore)%")
                    .font(.caption.bold()).foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Offre compatible détectée").font(.subheadline.weight(.semibold))
                Text("Correspondance ≥ 40 % avec ton profil").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                matchAnalysis = analysis
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
            Button("Importer") {
                let toImport = analysis
                autoMatch = nil
                Task { await model.clearHighlight() }
                importCurrentPage(matchScore: toImport.overallScore)
            }
            .buttonStyle(.borderedProminent)
            Button {
                autoMatch = nil
                Task { await model.clearHighlight() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 3)
    }

    /// Runs after each page finishes loading (when auto-scan is on): analyse the
    /// page and, if it matches the profile/CV at ≥ 40 %, outline it and offer to
    /// import. Silent on failure — it's a background convenience.
    private func autoScanIfNeeded() {
        guard model.autoScanEnabled, !importing, !scanning else { return }
        guard let url = model.currentURL, url.scheme?.hasPrefix("http") == true,
              model.markScannedIfNew(url) else { return }
        let profile = ProfileStore().load().promptContext
        // Nothing to match against → skip.
        guard !profile.isEmpty || defaultResumeText != nil else { return }

        scanning = true
        Task {
            defer { scanning = false }
            guard let text = await model.captureVisibleText(),
                  WebViewModel.looksLikeJobPage(text) else { return }
            do {
                let analysis = try await services.claude.analyzePageMatch(
                    pageText: String(text.prefix(6000)),
                    profile: profile.isEmpty ? nil : profile,
                    resumeText: defaultResumeText)
                guard analysis.overallScore >= 40 else { return }
                withAnimation { autoMatch = analysis }
                await model.highlightMatch(score: analysis.overallScore)
            } catch {
                // Auto-scan stays silent; the manual "Analyser" action reports errors.
            }
        }
    }

    // MARK: Match analysis

    private func analyzePage() {
        importing = true
        Task {
            defer { importing = false }
            guard let text = await model.captureVisibleText(), text.count > 40 else {
                importMessage = "Page vide ou trop courte à analyser."
                return
            }
            do {
                let profile = ProfileStore().load().promptContext
                matchAnalysis = try await services.claude.analyzePageMatch(
                    pageText: text,
                    profile: profile.isEmpty ? nil : profile,
                    resumeText: defaultResumeText)
            } catch let error as ClaudeError {
                importMessage = error.errorDescription
            } catch {
                importMessage = error.localizedDescription
            }
        }
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

    // MARK: Full pipeline (import + prepare application draft)

    private func importAndPrepare() {
        importing = true
        Task {
            defer { importing = false }
            guard let text = await model.captureVisibleText(), text.count > 40 else {
                importMessage = "Page vide ou trop courte pour être importée."
                return
            }
            do {
                // 1) Read the page → structured offer.
                let parsed = try await services.claude.parseOffer(rawText: String(text.prefix(8000)))
                let offer = JobOffer(
                    title: parsed.title, company: parsed.company,
                    location: parsed.location, descriptionText: parsed.description,
                    sourceURL: model.currentURL?.absoluteString, needsParsing: false)
                if let region = FrenchRegion.detect(from: parsed.location) {
                    offer.tags.append(region.rawValue)
                }
                modelContext.insert(offer)
                try? modelContext.save()

                // 2) Draft the application email from profile + CV.
                let profileContext = ProfileStore().load().promptContext
                let draft = try await services.claude.generateEmail(
                    kind: .application,
                    offer: offer,
                    resumeText: defaultResumeText,
                    senderProfile: profileContext.isEmpty ? nil : profileContext,
                    tone: .formal)

                // 3) Deposit it as a draft.
                if services.gmail.isConnected {
                    try await services.gmail.createDraft(
                        to: offer.contactEmail ?? "",
                        subject: draft.subject,
                        body: draft.body)
                    importMessage = "✅ Offre importée + brouillon de candidature créé dans Gmail."
                } else {
                    offer.notes = "✉️ Brouillon de candidature — Objet : \(draft.subject)\n\n\(draft.body)"
                    try? modelContext.save()
                    importMessage = "✅ Offre importée + brouillon préparé dans les notes de l'offre. "
                        + "Connecte Gmail (Réglages) pour l'obtenir directement en brouillon d'email."
                }

                // Notify the user their draft is ready to finish sending.
                let company = offer.company.isEmpty ? "Nouvelle offre" : offer.company
                await NotificationService().notifyNow(
                    title: "Brouillon de candidature prêt",
                    body: "\(company) : viens compléter et envoyer ta candidature.")
            } catch let error as ClaudeError {
                importMessage = error.errorDescription
            } catch let error as GmailError {
                importMessage = error.errorDescription
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    // MARK: Import

    private func importCurrentPage(matchScore: Int? = nil) {
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
                    matchScore: matchScore,
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
