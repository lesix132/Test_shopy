import SwiftUI
import SwiftData

/// "Relances" tab: tracks applications, flags those needing a follow-up, and
/// drafts application/follow-up emails with Claude that you send from your own
/// mail app (JobTrack never sends silently).
struct FollowUpsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Query(sort: \JobOffer.dateAdded, order: .reverse) private var offers: [JobOffer]
    @Query private var resumes: [Resume]

    @State private var viewModel: FollowUpsViewModel?

    private var applied: [JobOffer] { offers.filter { $0.status == .applied } }
    private var toFollowUp: [JobOffer] { applied.filter { $0.needsFollowUp() && !$0.hasReply } }
    private var waiting: [JobOffer] { applied.filter { !$0.needsFollowUp() && !$0.hasReply } }
    private var replied: [JobOffer] { applied.filter { $0.hasReply } }

    private var defaultResumeText: String? {
        (resumes.first(where: \.isDefault) ?? resumes.first)?.extractedText
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Relances")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FollowUpsViewModel(claude: services.claude)
            }
        }
        .task {
            let service = NotificationService()
            await service.requestAuthorization()
            await service.rescheduleFollowUps(for: offers)
        }
    }

    @ViewBuilder
    private func content(_ vm: FollowUpsViewModel) -> some View {
        List {
            if applied.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune candidature suivie", systemImage: "paperplane")
                    } description: {
                        Text("Passe une offre au statut « Candidature envoyée » pour "
                             + "la suivre ici et être relancé automatiquement.")
                    }
                }
            }

            if !toFollowUp.isEmpty {
                Section("À relancer maintenant") {
                    ForEach(toFollowUp) { offer in row(offer, vm: vm, due: true) }
                }
            }
            if !waiting.isEmpty {
                Section("En attente de réponse") {
                    ForEach(waiting) { offer in row(offer, vm: vm, due: false) }
                }
            }
            if !replied.isEmpty {
                Section("Réponse reçue") {
                    ForEach(replied) { offer in row(offer, vm: vm, due: false) }
                }
            }
        }
        .sheet(item: draftBinding(vm)) { _ in
            if let draft = vm.draft {
                EmailDraftSheet(
                    draft: draft,
                    recipient: offer(for: vm.draftOfferID)?.contactEmail,
                    onSent: {
                        if let offer = offer(for: vm.draftOfferID) {
                            markContacted(offer)
                        }
                        vm.clearDraft()
                    },
                    onClose: { vm.clearDraft() }
                )
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ offer: JobOffer, vm: FollowUpsViewModel, due: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.company.isEmpty ? offer.displayTitle : offer.company)
                .font(.headline)
            if !offer.title.isEmpty {
                Text(offer.title).font(.subheadline).foregroundStyle(.secondary)
            }
            followUpStatus(offer, due: due)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await vm.generate(
                            kind: due ? .followUp : .application,
                            offer: offer,
                            resumeText: defaultResumeText)
                    }
                } label: {
                    if vm.isGenerating {
                        ProgressView()
                    } else {
                        Label(due ? "Relancer (IA)" : "Rédiger (IA)",
                              systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(vm.isGenerating)

                Spacer()

                Menu {
                    Button("Marquer relancé aujourd'hui") { markContacted(offer) }
                    Button("Réponse reçue") { markReplied(offer) }
                    if offer.hasReply {
                        Button("Annuler « réponse reçue »") { offer.hasReply = false; save() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .font(.callout)

            if let error = vm.errorMessage, vm.draftOfferID == nil {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func followUpStatus(_ offer: JobOffer, due: Bool) -> some View {
        if offer.hasReply {
            Label("Réponse reçue", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.green)
        } else if due {
            Label("Relance conseillée", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        } else if let next = offer.nextFollowUpDate() {
            Label("Relance le \(next.formatted(date: .abbreviated, time: .omitted))",
                  systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func offer(for id: UUID?) -> JobOffer? {
        guard let id else { return nil }
        return offers.first { $0.id == id }
    }

    /// A binding that presents the draft sheet when a draft exists.
    private func draftBinding(_ vm: FollowUpsViewModel) -> Binding<DraftToken?> {
        Binding(
            get: { vm.draft == nil ? nil : DraftToken(id: vm.draftOfferID ?? UUID()) },
            set: { if $0 == nil { vm.clearDraft() } }
        )
    }

    private func markContacted(_ offer: JobOffer) {
        offer.lastContactAt = .now
        save()
    }

    private func markReplied(_ offer: JobOffer) {
        offer.hasReply = true
        save()
    }

    private func save() {
        try? modelContext.save()
        Task { await NotificationService().rescheduleFollowUps(for: offers) }
    }
}

/// Identifiable token so `.sheet(item:)` can present the draft.
private struct DraftToken: Identifiable, Equatable {
    let id: UUID
}
