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

    /// Originals first; each AI-optimized copy is listed right under its source.
    private var orderedResumes: [Resume] {
        let roots = resumes.filter { !$0.isTailored }
        var result: [Resume] = []
        for root in roots {
            result.append(root)
            result.append(contentsOf: resumes
                .filter { $0.sourceResumeID == root.id }
                .sorted { $0.dateUpdated > $1.dateUpdated })
        }
        let shown = Set(result.map(\.id))
        result.append(contentsOf: resumes.filter { !shown.contains($0.id) })
        return result
    }

    private var list: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            ForEach(orderedResumes) { resume in
                NavigationLink {
                    ResumeTextView(resume: resume)
                } label: {
                    resumeRow(resume)
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

    @ViewBuilder
    private func resumeRow(_ resume: Resume) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if resume.isTailored {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                }
                Text(resume.name).font(resume.isTailored ? .subheadline.weight(.medium) : .headline)
                if resume.isDefault {
                    Text("Par défaut")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            if resume.isTailored, let target = resume.tailoredForOffer {
                Label("Optimisé pour : \(target)", systemImage: "wand.and.stars")
                    .font(.caption).foregroundStyle(.indigo)
                if let reason = resume.tailoringReason, !reason.isEmpty {
                    Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text("Mis à jour le \(resume.dateUpdated.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, resume.isTailored ? 12 : 0)
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
