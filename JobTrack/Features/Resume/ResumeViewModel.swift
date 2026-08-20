import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ResumeViewModel {
    var errorMessage: String?

    /// Import a PDF from a security-scoped URL (file picker result).
    func importPDF(from url: URL, name: String?, into context: ModelContext, resumes: [Resume]) {
        errorMessage = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let text = PDFService.extractText(from: data)
            let label = (name?.isEmpty == false ? name! : url.deletingPathExtension().lastPathComponent)
            let resume = Resume(
                name: label,
                pdfData: data,
                extractedText: text,
                isDefault: resumes.isEmpty   // first CV becomes default
            )
            context.insert(resume)
            try context.save()
            if text.isEmpty {
                errorMessage = "Le PDF ne contient pas de texte extractible (peut-être scanné). "
                    + "Le CV est enregistré mais la génération sera limitée."
            }
        } catch {
            errorMessage = "Import impossible : \(error.localizedDescription)"
        }
    }

    func makeDefault(_ resume: Resume, in resumes: [Resume], context: ModelContext) {
        for other in resumes { other.isDefault = false }
        resume.isDefault = true
        try? context.save()
    }

    func delete(_ resume: Resume, in resumes: [Resume], context: ModelContext) {
        let wasDefault = resume.isDefault
        context.delete(resume)
        if wasDefault, let next = resumes.first(where: { $0.id != resume.id }) {
            next.isDefault = true
        }
        try? context.save()
    }
}
