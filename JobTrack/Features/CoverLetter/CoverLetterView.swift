import SwiftUI
import SwiftData

struct CoverLetterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let offer: JobOffer
    let resume: Resume?
    let existingLetter: CoverLetter?

    @State private var viewModel: CoverLetterViewModel?
    @State private var exportURL: URL?
    @State private var showingShare = false

    init(offer: JobOffer, resume: Resume?, existingLetter: CoverLetter? = nil) {
        self.offer = offer
        self.resume = resume
        self.existingLetter = existingLetter
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
            .navigationTitle("Lettre de motivation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CoverLetterViewModel(
                    claude: services.claude,
                    offer: offer,
                    resume: resume,
                    existingLetter: existingLetter
                )
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        #endif
    }

    @ViewBuilder
    private func content(_ vm: CoverLetterViewModel) -> some View {
        @Bindable var vm = vm
        Form {
            Section("Paramètres") {
                Picker("Ton", selection: $vm.tone) {
                    ForEach(LetterTone.allCases) { Text($0.label).tag($0) }
                }
                Picker("Longueur", selection: $vm.length) {
                    ForEach(LetterLength.allCases) { Text($0.label).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Instructions supplémentaires (optionnel)")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $vm.extraInstructions).frame(minHeight: 44)
                }
                Button {
                    Task { await vm.generate() }
                } label: {
                    if vm.isGenerating {
                        HStack { ProgressView(); Text("Génération…") }
                    } else {
                        Label(vm.content.isEmpty ? "Générer" : "Régénérer",
                              systemImage: "wand.and.stars")
                    }
                }
                .disabled(!vm.canGenerate)

                if vm.missingResume {
                    Label("Aucun CV disponible. Ajoutez-en un dans l'onglet CV.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let error = vm.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }

            Section("Lettre (éditable)") {
                TextEditor(text: $vm.content)
                    .frame(minHeight: 260)
                    .font(.callout)
            }

            if let letter = vm.letter {
                Section("Statut") {
                    Picker("Statut", selection: Binding(
                        get: { letter.status },
                        set: { vm.setStatus($0, context: modelContext) }
                    )) {
                        ForEach(LetterStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
            }

            Section {
                Button {
                    Pasteboard.copy(vm.content)
                } label: {
                    Label("Copier le texte", systemImage: "doc.on.doc")
                }
                .disabled(vm.content.isEmpty)

                Button {
                    if let url = vm.exportPDF() {
                        exportURL = url
                        #if os(iOS)
                        showingShare = true
                        #elseif os(macOS)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        #endif
                    }
                } label: {
                    Label("Exporter en PDF", systemImage: "arrow.down.doc")
                }
                .disabled(vm.content.isEmpty)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fermer") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Enregistrer") {
                viewModel?.save(into: modelContext)
                dismiss()
            }
            .disabled((viewModel?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

#if os(iOS)
import UIKit
/// Bridges `UIActivityViewController` for sharing/exporting the PDF.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit
#endif
