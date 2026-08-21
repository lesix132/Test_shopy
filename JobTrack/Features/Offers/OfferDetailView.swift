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

    private var defaultResume: Resume? {
        resumes.first(where: \.isDefault) ?? resumes.first
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
