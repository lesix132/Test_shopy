import SwiftUI

/// Read-only view of a CV's extracted text. For AI-optimized copies it shows
/// what it was tailored for and why, above the same body of text as the
/// original.
struct ResumeTextView: View {
    let resume: Resume
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if resume.isTailored {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Copie optimisée par l'IA", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                        if let target = resume.tailoredForOffer {
                            Text("Pour l'offre : \(target)").font(.callout)
                        }
                        if let reason = resume.tailoringReason, !reason.isEmpty {
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Ton CV d'origine reste intact dans la liste.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Text(resume.extractedText.isEmpty
                     ? "Aucun texte extrait pour ce CV."
                     : resume.extractedText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(resume.isTailored ? "CV optimisé" : "CV")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Pasteboard.copy(resume.extractedText)
                    copied = true
                } label: {
                    Label(copied ? "Copié ✓" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(resume.extractedText.isEmpty)
            }
        }
    }
}
