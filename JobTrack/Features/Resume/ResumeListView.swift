import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ResumeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Resume.dateUpdated, order: .reverse) private var resumes: [Resume]
    @State private var viewModel = ResumeViewModel()
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if resumes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Mes CV")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImporter = true } label: {
                        Label("Ajouter un CV", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.importPDF(from: url, name: nil, into: modelContext, resumes: resumes)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var list: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            ForEach(resumes) { resume in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(resume.name).font(.headline)
                        if resume.isDefault {
                            Text("Par défaut")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    Text("Mis à jour le \(resume.dateUpdated.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(resume.extractedText.isEmpty
                         ? "Aucun texte extrait"
                         : "\(resume.extractedText.count) caractères extraits")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.delete(resume, in: resumes, context: modelContext)
                    } label: { Label("Supprimer", systemImage: "trash") }

                    if !resume.isDefault {
                        Button {
                            viewModel.makeDefault(resume, in: resumes, context: modelContext)
                        } label: { Label("Par défaut", systemImage: "star") }
                        .tint(.blue)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun CV", systemImage: "doc.text")
        } description: {
            Text("Importez votre CV au format PDF. Vous pouvez en stocker plusieurs versions (généraliste, spécialisé…).")
        } actions: {
            Button("Importer un PDF") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
