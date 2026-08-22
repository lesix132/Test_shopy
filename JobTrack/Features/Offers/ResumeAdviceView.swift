import SwiftUI

/// Shows Claude's ATS optimisation advice for a CV against a specific offer.
struct ResumeAdviceView: View {
    let advice: ResumeAdvice
    let offer: JobOffer
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(scoreColor.opacity(0.2), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: CGFloat(advice.atsScore) / 100)
                                .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(advice.atsScore)%").font(.headline.bold())
                        }
                        .frame(width: 66, height: 66)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Score ATS estimé").font(.subheadline.weight(.semibold))
                            Text("Probabilité de passer le tri automatique de cette offre.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !advice.missingKeywords.isEmpty {
                    Section("Mots-clés à ajouter (si vrais pour toi)") {
                        keywordWrap(advice.missingKeywords, tint: .orange)
                    }
                }
                if !advice.presentKeywords.isEmpty {
                    Section("Déjà présents dans ton CV") {
                        keywordWrap(advice.presentKeywords, tint: .green)
                    }
                }

                if !advice.suggestions.isEmpty {
                    Section("Recommandations") {
                        ForEach(Array(advice.suggestions.enumerated()), id: \.offset) { _, tip in
                            Label {
                                Text(tip)
                            } icon: {
                                Image(systemName: "checkmark.circle").foregroundStyle(.tint)
                            }
                            .font(.callout)
                        }
                    }
                }

                if !advice.optimizedSummary.isEmpty {
                    Section {
                        Text(advice.optimizedSummary)
                            .font(.callout).textSelection(.enabled)
                        Button {
                            Pasteboard.copy(advice.optimizedSummary)
                            copied = true
                        } label: {
                            Label(copied ? "Copié ✓" : "Copier l'accroche",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    } header: {
                        Text("Accroche optimisée")
                    } footer: {
                        Text("Colle-la en haut de ton CV, adaptée à « \(offer.title) ».")
                    }
                }
            }
            .navigationTitle("Optimisation ATS")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var scoreColor: Color {
        switch advice.atsScore {
        case 70...: return .green
        case 45..<70: return .orange
        default: return .red
        }
    }

    /// Simple flowing chips using an adaptive grid.
    private func keywordWrap(_ items: [String], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { kw in
                Text(kw)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }
}
