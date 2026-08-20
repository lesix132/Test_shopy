import SwiftUI

/// Small colored badge showing an application status.
struct StatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .toProcess: return .gray
        case .applied:   return .blue
        case .interview: return .orange
        case .rejected:  return .red
        case .accepted:  return .green
        }
    }
}

/// Badge for a cover-letter status.
struct LetterStatusBadge: View {
    let status: LetterStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .draft:     return .gray
        case .finalized: return .indigo
        case .sent:      return .green
        }
    }
}
