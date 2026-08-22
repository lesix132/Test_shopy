import SwiftUI
import SwiftData

/// Home screen: a at-a-glance overview of the whole job search — key numbers,
/// the application pipeline, and the follow-ups that need action right now.
/// It reads the same SwiftData store as the other tabs, so it always reflects
/// live state without any extra bookkeeping.
struct DashboardView: View {
    @Query(sort: \JobOffer.dateAdded, order: .reverse) private var offers: [JobOffer]

    private var stats: DashboardStats { DashboardStats(offers: offers) }
    private var greetingName: String {
        let name = ProfileStore().load().fullName
            .split(separator: " ").first.map(String.init) ?? ""
        return name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if offers.isEmpty {
                        emptyState
                    } else {
                        kpiGrid
                        followUpsCard
                        pipelineCard
                        responseCard
                        recentCard
                    }
                }
                .padding()
            }
            .navigationTitle("Tableau de bord")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingName.isEmpty ? "Bonjour 👋" : "Bonjour \(greetingName) 👋")
                .font(.largeTitle.bold())
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: KPI grid

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            KPICard(title: "Offres suivies", value: "\(stats.total)",
                    icon: "briefcase.fill", tint: .indigo)
            KPICard(title: "Candidatures", value: "\(stats.applied)",
                    icon: "paperplane.fill", tint: .blue)
            KPICard(title: "Entretiens", value: "\(stats.interviews)",
                    icon: "person.2.wave.2.fill", tint: .orange)
            KPICard(title: "Relances à faire", value: "\(stats.dueFollowUps.count)",
                    icon: "bell.badge.fill", tint: stats.dueFollowUps.isEmpty ? .green : .red)
        }
    }

    // MARK: Follow-ups

    @ViewBuilder
    private var followUpsCard: some View {
        DashboardCard(title: "Relances à faire", systemImage: "bell.badge") {
            if stats.dueFollowUps.isEmpty {
                Label("Tu es à jour, aucune relance en attente 🎉", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stats.dueFollowUps.prefix(4)) { offer in
                    NavigationLink { OfferDetailView(offer: offer) } label: {
                        followUpRow(offer, overdue: true)
                    }
                    .buttonStyle(.plain)
                }
                if stats.dueFollowUps.count > 4 {
                    Text("+ \(stats.dueFollowUps.count - 4) autre(s)…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !stats.upcomingFollowUps.isEmpty {
                Divider().padding(.vertical, 2)
                Text("À venir").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(stats.upcomingFollowUps.prefix(3)) { offer in
                    NavigationLink { OfferDetailView(offer: offer) } label: {
                        followUpRow(offer, overdue: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func followUpRow(_ offer: JobOffer, overdue: Bool) -> some View {
        HStack {
            Circle().fill(overdue ? Color.red : Color.orange).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.displayTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                if !offer.company.isEmpty {
                    Text(offer.company).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let due = offer.nextFollowUpDate() {
                Text(due, format: .dateTime.day().month(.abbreviated))
                    .font(.caption).foregroundStyle(overdue ? .red : .secondary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Pipeline

    private var pipelineCard: some View {
        DashboardCard(title: "Pipeline", systemImage: "chart.bar.xaxis") {
            ForEach(ApplicationStatus.allCases) { status in
                let count = stats.count(for: status)
                HStack(spacing: 10) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.tint)
                        .frame(width: 20)
                    Text(status.label).font(.subheadline)
                    Spacer()
                    ProgressView(value: Double(count), total: Double(max(stats.total, 1)))
                        .tint(status.tint)
                        .frame(width: 90)
                    Text("\(count)").font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Response rate

    @ViewBuilder
    private var responseCard: some View {
        if stats.applied > 0 {
            DashboardCard(title: "Taux de réponse", systemImage: "envelope.badge") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.responseRate)%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                    Text("(\(stats.replies)/\(stats.applied) réponses)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(stats.responseRate >= 20
                     ? "Bon taux — continue comme ça."
                     : "Astuce : personnalise davantage tes messages et relance après quelques jours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Recent activity

    @ViewBuilder
    private var recentCard: some View {
        if stats.addedLast7Days > 0 {
            DashboardCard(title: "Cette semaine", systemImage: "calendar") {
                Label("\(stats.addedLast7Days) offre(s) ajoutée(s) ces 7 derniers jours",
                      systemImage: "plus.circle")
                    .font(.subheadline)
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ta recherche démarre ici", systemImage: "chart.pie")
        } description: {
            Text("Ajoute des offres depuis l'onglet Offres, le Fil ou le navigateur Web. "
                 + "Ce tableau de bord se remplira automatiquement.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Computed stats

/// Derives all the dashboard numbers from the offers, in one pass where it
/// matters. Kept as a plain value type so it is trivial to unit-test.
struct DashboardStats {
    let offers: [JobOffer]

    var total: Int { offers.count }

    /// Every offer that has reached (at least) the "applied" stage.
    var applied: Int {
        offers.filter { $0.appliedAt != nil || $0.status != .toProcess }.count
    }
    var interviews: Int { count(for: .interview) }
    var replies: Int { offers.filter { $0.hasReply }.count }

    func count(for status: ApplicationStatus) -> Int {
        offers.filter { $0.status == status }.count
    }

    /// Reply rate over applied offers (0–100).
    var responseRate: Int {
        guard applied > 0 else { return 0 }
        return Int((Double(replies) / Double(applied) * 100).rounded())
    }

    /// Offers whose follow-up is due now, soonest first.
    var dueFollowUps: [JobOffer] {
        offers.filter { $0.needsFollowUp() }
            .sorted { ($0.nextFollowUpDate() ?? .distantFuture) < ($1.nextFollowUpDate() ?? .distantFuture) }
    }

    /// Applied offers awaiting a reply whose follow-up is still in the future.
    var upcomingFollowUps: [JobOffer] {
        let now = Date.now
        return offers.filter {
            $0.status == .applied && !$0.hasReply
                && ($0.nextFollowUpDate().map { $0 > now } ?? false)
        }
        .sorted { ($0.nextFollowUpDate() ?? .distantFuture) < ($1.nextFollowUpDate() ?? .distantFuture) }
    }

    var addedLast7Days: Int {
        let cutoff = Date.now.addingTimeInterval(-7 * 86_400)
        return offers.filter { $0.dateAdded >= cutoff }.count
    }
}

// MARK: - Reusable card views

private struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        #else
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        #endif
    }
}
