import SwiftUI
import SwiftData

struct AddOfferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// When set, we're finishing the import of a Share-Extension / inbox item.
    let existingOffer: JobOffer?
    /// Name of the source (LinkedIn, Indeed…) to show tailored import guidance.
    let sourceHint: String?

    @State private var viewModel: AddOfferViewModel?

    init(existingOffer: JobOffer? = nil, sourceHint: String? = nil) {
        self.existingOffer = existingOffer
        self.sourceHint = sourceHint
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
            .navigationTitle(existingOffer == nil ? "Nouvelle offre" : "Confirmer l'import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .top) {
                if let viewModel { saveBar(viewModel) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        #endif
        .onAppear {
            if viewModel == nil {
                let vm = AddOfferViewModel(claude: services.claude)
                if let existingOffer { vm.load(from: existingOffer) }
                viewModel = vm
            }
        }
    }

    /// Prominent "save" action pinned at the top of the floating sheet.
    private func saveBar(_ vm: AddOfferViewModel) -> some View {
        Button {
            vm.save(into: modelContext, existing: existingOffer)
            dismiss()
        } label: {
            Label("Enregistrer l'offre", systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.canSave)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func content(_ vm: AddOfferViewModel) -> some View {
        @Bindable var vm = vm
        Form {
            if let sourceHint {
                Section {
                    Label {
                        Text("Ouvre l'offre sur \(sourceHint), copie son texte (ou "
                             + "partage-la vers JobTrack), puis colle-le ci-dessous : "
                             + "l'IA extrait le titre, l'entreprise et le lieu.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "square.and.arrow.down.on.square").foregroundStyle(.blue)
                    }
                }
            }
            captureSection(vm)

            if vm.hasContent {
                fieldsSection(vm)
                metaSection(vm)
            }

            if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    // MARK: - Capture (paste / OCR / parse)

    @ViewBuilder
    private func captureSection(_ vm: AddOfferViewModel) -> some View {
        @Bindable var vm = vm
        Section("Coller l'offre") {
            TextEditor(text: $vm.rawText)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if vm.rawText.isEmpty {
                        Text("Collez ici le texte de l'offre (LinkedIn, page web…)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                Task { await vm.parseWithClaude() }
            } label: {
                if vm.isParsing {
                    HStack { ProgressView(); Text("Analyse avec Claude…") }
                } else {
                    Label("Analyser avec Claude", systemImage: "wand.and.stars")
                }
            }
            .disabled(vm.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isParsing)

            Button {
                if let data = Pasteboard.imageData() {
                    Task { await vm.runOCR(on: data) }
                } else {
                    vm.errorMessage = "Aucune image dans le presse-papiers."
                }
            } label: {
                if vm.isRunningOCR {
                    HStack { ProgressView(); Text("OCR en cours…") }
                } else {
                    Label("OCR depuis le presse-papiers", systemImage: "text.viewfinder")
                }
            }
            .disabled(vm.isRunningOCR)

            Button {
                vm.useRawTextManually()
            } label: {
                Label("Saisir / éditer manuellement", systemImage: "pencil")
            }
        }
    }

    // MARK: - Editable fields

    @ViewBuilder
    private func fieldsSection(_ vm: AddOfferViewModel) -> some View {
        @Bindable var vm = vm
        Section("Détails") {
            TextField("Intitulé du poste", text: $vm.title)
            TextField("Entreprise", text: $vm.company)
            TextField("Lieu", text: $vm.location)
            TextField("URL source", text: $vm.sourceURL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            VStack(alignment: .leading) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $vm.descriptionText).frame(minHeight: 140)
            }
        }
    }

    @ViewBuilder
    private func metaSection(_ vm: AddOfferViewModel) -> some View {
        @Bindable var vm = vm
        Section("Organisation") {
            TagEditor(tags: $vm.tags)
            VStack(alignment: .leading) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $vm.notes).frame(minHeight: 60)
            }
        }
    }
}

/// Cross-platform pasteboard image access.
enum Pasteboard {
    static func imageData() -> Data? {
        #if canImport(UIKit)
        return imageDataUIKit()
        #elseif canImport(AppKit)
        return imageDataAppKit()
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private static func imageDataUIKit() -> Data? {
        UIPasteboard.general.image?.pngData()
    }
    #endif

    #if canImport(AppKit)
    private static func imageDataAppKit() -> Data? {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            return nil
        }
        return image.tiffRepresentation
    }
    #endif

    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
