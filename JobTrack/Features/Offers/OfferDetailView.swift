import SwiftUI
import SwiftData

struct OfferDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Bindable var offer: JobOffer

    @Query private var resumes: [Resume]
    @State private var viewModel: OfferDetailViewModel?
    @State private var showingGenerator = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingAdvice = false
    @State private var preparing = false
    @State private var prepareMessage: String?

    private var defaultResume: Resume? {
        resumes.first(where: \.isDefault) ?? resumes.first
    }

    /// The default CV as a mail attachment, if one is stored.
    private var cvAttachment: EmailAttachment? {
        guard let cv = defaultResume, !cv.pdfData.isEmpty else { return nil }
        let name = cv.name.isEmpty ? "CV" : cv.name
        return EmailAttachment(filename: "\(name).pdf", mimeType: "application/pdf", data: cv.pdfData)
    }

    var body: some View {
        Form {
            if offer.needsParsing {
                Section {
                    Label("Cette offre a été importée mais pas encore analysée.",
                          systemImage: "wand.and.stars")
                        .foregroundStyle(.orange)
                    Button("Analyser / compléter") { showingEdit = true }
                }
            }

            headerSection
            statusSection
            followUpSection
            descriptionSection
            organizationSection
            matchSection
            atsSection
            automationSection
            lettersSection
            deleteSection
        }
        .navigationTitle(offer.company.isEmpty ? "Offre" : offer.company)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Éditer") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddOfferView(existingOffer: offer)
        }
        .sheet(isPresented: $showingGenerator) {
            CoverLetterView(offer: offer, resume: defaultResume)
        }
        .sheet(isPresented: $showingAdvice) {
            if let advice = viewModel?.advice {
                ResumeAdviceView(advice: advice, offer: offer)
            }
        }
        .alert("Automatisation", isPresented: Binding(
            get: { prepareMessage != nil },
            set: { if !$0 { prepareMessage = nil } }
        )) {
            Button("OK", role: .cancel) { prepareMessage = nil }
        } message: {
            Text(prepareMessage ?? "")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = OfferDetailViewModel(claude: services.claude)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            if !offer.title.isEmpty {
                Text(offer.title).font(.title3.weight(.semibold))
            }
            if !offer.location.isEmpty {
                Label(offer.location, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            }
            if let urlString = offer.sourceURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Ouvrir la source", systemImage: "link")
                }
            }
            LabeledContent("Ajoutée le", value: offer.dateAdded.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var statusSection: some View {
        Section("Statut") {
            Picker("Statut de candidature", selection: Binding(
                get: { offer.status },
                set: { newStatus in
                    offer.status = newStatus
                    // Starting the application sets its date so follow-ups work.
                    if newStatus == .applied, offer.appliedAt == nil {
                        offer.appliedAt = .now
                    }
                    try? modelContext.save()
                }
            )) {
                ForEach(ApplicationStatus.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var followUpSection: some View {
        Section {
            TextField("Email du recruteur (pour candidature / relance)", text: Binding(
                get: { offer.contactEmail ?? "" },
                set: { offer.contactEmail = $0.isEmpty ? nil : $0 }
            ))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            #endif
            .autocorrectionDisabled()

            if offer.status == .applied {
                if let applied = offer.appliedAt {
                    LabeledContent("Candidaté le",
                                   value: applied.formatted(date: .abbreviated, time: .omitted))
                } else {
                    Button("Marquer candidaté aujourd'hui") {
                        offer.appliedAt = .now
                        try? modelContext.save()
                    }
                }
                Stepper("Relance après \(offer.followUpAfterDays) j",
                        value: $offer.followUpAfterDays, in: 1...60)
                Toggle("Réponse reçue", isOn: $offer.hasReply)
            } else {
                Button {
                    offer.status = .applied
                    offer.appliedAt = .now
                    try? modelContext.save()
                } label: {
                    Label("Marquer comme candidaté", systemImage: "paperplane")
                }
            }
        } header: {
            Text("Suivi de candidature")
        } footer: {
            Text("Une candidature envoyée apparaît dans l'onglet Relances, "
                 + "avec rappel automatique si pas de réponse.")
        }
        .onDisappear { try? modelContext.save() }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if !offer.descriptionText.isEmpty {
            Section("Description") {
                Text(offer.descriptionText)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private var organizationSection: some View {
        Section("Organisation") {
            if !offer.tags.isEmpty { TagChips(tags: offer.tags) }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { offer.notes },
                    set: { offer.notes = $0 }
                ))
                .frame(minHeight: 60)
                .onDisappear { try? modelContext.save() }
            }
        }
    }

    @ViewBuilder
    private var matchSection: some View {
        Section("Pertinence CV / offre") {
            if let score = offer.matchScore {
                LabeledContent("Score", value: "\(score)%")
            }
            Button {
                Task {
                    await viewModel?.computeMatchScore(
                        for: offer, resume: defaultResume, context: modelContext
                    )
                }
            } label: {
                if viewModel?.isScoring == true {
                    HStack { ProgressView(); Text("Calcul…") }
                } else {
                    Label(offer.matchScore == nil ? "Calculer le score" : "Recalculer",
                          systemImage: "target")
                }
            }
            .disabled(viewModel?.isScoring == true)
            if let error = viewModel?.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var atsSection: some View {
        Section {
            Button {
                Task {
                    await viewModel?.tailorResume(for: offer, resume: defaultResume)
                    if let advice = viewModel?.advice {
                        createTailoredCV(from: advice)
                        showingAdvice = true
                    }
                }
            } label: {
                if viewModel?.isTailoring == true {
                    HStack { ProgressView(); Text("Optimisation…") }
                } else {
                    Label("Optimiser mon CV pour cette offre (ATS)",
                          systemImage: "wand.and.stars.inverse")
                }
            }
            .disabled(viewModel?.isTailoring == true || defaultResume == nil)

            if defaultResume == nil {
                Text("Ajoute d'abord un CV dans l'onglet CV.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let advice = viewModel?.advice {
                LabeledContent("Score ATS estimé", value: "\(advice.atsScore)%")
                Button("Voir les recommandations") { showingAdvice = true }
            }
        } header: {
            Text("Optimisation CV (ATS)")
        } footer: {
            Text("L'IA crée une copie optimisée de ton CV pour cette offre (dans "
                 + "l'onglet CV, sous l'original) et te montre les changements. "
                 + "Honnête : elle réorganise et reformule, sans rien inventer.")
        }
    }

    /// Creates an AI-optimized copy of the default CV, tailored to this offer,
    /// keeping the original untouched. Appears in the CV tab under its source.
    private func createTailoredCV(from advice: ResumeAdvice) {
        guard let original = defaultResume,
              !advice.optimizedResumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let target = [offer.title, offer.company]
            .filter { !$0.isEmpty }.joined(separator: " — ")
        let label = offer.title.isEmpty ? offer.company : offer.title
        let pdf = PDFService.makePDF(from: advice.optimizedResumeText,
                                     title: "CV — \(target)")
        let copy = Resume(
            name: "CV optimisé — \(label)",
            pdfData: pdf,
            extractedText: advice.optimizedResumeText,
            isDefault: false,
            sourceResumeID: original.id,
            tailoredForOffer: target.isEmpty ? offer.company : target,
            tailoringReason: tailoringReason(from: advice))
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func tailoringReason(from advice: ResumeAdvice) -> String {
        var parts: [String] = []
        if !advice.missingKeywords.isEmpty {
            parts.append("Mots-clés intégrés : "
                         + advice.missingKeywords.prefix(6).joined(separator: ", "))
        }
        if let first = advice.suggestions.first { parts.append(first) }
        parts.append("Score ATS estimé : \(advice.atsScore)%")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var automationSection: some View {
        Section {
            Button {
                prepareDraft()
            } label: {
                if preparing {
                    HStack { ProgressView(); Text("Préparation…") }
                } else {
                    Label("Préparer le mail de candidature (brouillon)",
                          systemImage: "wand.and.stars")
                }
            }
            .disabled(preparing)
        } header: {
            Text("Automatisation")
        } footer: {
            Text("L'IA relève l'email du recruteur, rédige un mail (objet + accroche) "
                 + "et le dépose en brouillon Gmail avec ton CV joint (sinon dans les notes).")
        }
    }

    /// Runs the "prepare application draft" pipeline for this saved offer.
    private func prepareDraft() {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                // Make sure we have a recruiter email (scan description + notes).
                if (offer.contactEmail ?? "").isEmpty,
                   let found = WebViewModel.firstEmail(in: offer.descriptionText + "\n" + offer.notes) {
                    offer.contactEmail = found
                    try? modelContext.save()
                }
                let profileContext = ProfileStore().load().promptContext
                let cvText = defaultResume?.extractedText
                let draft = try await services.claude.generateEmail(
                    kind: .application,
                    offer: offer,
                    resumeText: (cvText?.isEmpty == false) ? cvText : nil,
                    senderProfile: profileContext.isEmpty ? nil : profileContext,
                    tone: .formal)

                let email = offer.contactEmail ?? ""
                let toLabel = email.isEmpty ? " (destinataire à compléter)" : " (à : \(email))"
                let cvNote = cvAttachment != nil ? " CV joint." : ""
                if services.gmail.isConnected {
                    try await services.gmail.createDraft(
                        to: email, subject: draft.subject, body: draft.body,
                        attachment: cvAttachment)
                    prepareMessage = "✅ Brouillon Gmail prêt\(toLabel).\(cvNote)"
                } else {
                    let to = email.isEmpty ? "—" : email
                    offer.notes = "✉️ Brouillon de candidature\nÀ : \(to)\nObjet : "
                        + "\(draft.subject)\n\n\(draft.body)"
                        + (offer.notes.isEmpty ? "" : "\n\n---\n\(offer.notes)")
                    try? modelContext.save()
                    prepareMessage = "✅ Brouillon préparé dans les notes\(toLabel). "
                        + "Connecte Gmail (Réglages) pour l'obtenir en brouillon email avec CV joint."
                }
            } catch let error as ClaudeError {
                prepareMessage = error.errorDescription
            } catch let error as GmailError {
                prepareMessage = error.errorDescription
            } catch {
                prepareMessage = error.localizedDescription
            }
        }
    }

    private var lettersSection: some View {
        Section("Lettres de motivation") {
            Button {
                showingGenerator = true
            } label: {
                Label("Générer une lettre", systemImage: "square.and.pencil")
            }

            if offer.coverLetters.isEmpty {
                Text("Aucune lettre pour le moment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(offer.coverLetters.sorted { $0.dateGenerated > $1.dateGenerated }) { letter in
                    NavigationLink {
                        CoverLetterView(offer: offer, resume: defaultResume, existingLetter: letter)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(letter.dateGenerated, style: .date)
                                Spacer()
                                LetterStatusBadge(status: letter.status)
                            }
                            Text(letter.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: deleteLetters)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Supprimer cette offre", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .confirmationDialog(
                "Supprimer définitivement cette offre et ses lettres ?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    modelContext.delete(offer)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func deleteLetters(at offsets: IndexSet) {
        let sorted = offer.coverLetters.sorted { $0.dateGenerated > $1.dateGenerated }
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        try? modelContext.save()
    }
}
