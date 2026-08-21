import SwiftUI

/// Shows the AI match analysis of the current page: an overall score plus a
/// line-by-line breakdown (match / no match + percentage) vs the profile & CV.
struct PageMatchView: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: PageMatchAnalysis

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        scoreRing(analysis.overallScore)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Correspondance globale").font(.headline)
                            if !analysis.summary.isEmpty {
                                Text(analysis.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Critères") {
                    ForEach(analysis.lines) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: line.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(line.matches ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.criterion).font(.subheadline.weight(.medium))
                                if !line.comment.isEmpty {
                                    Text(line.comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(line.score)%")
                                .font(.caption.bold())
                                .foregroundStyle(color(for: line.score))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Correspondance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func scoreRing(_ score: Int) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color(for: score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)%").font(.headline).bold()
        }
        .frame(width: 64, height: 64)
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 75...:   return .green
        case 50..<75: return .orange
        default:      return .red
        }
    }
}
