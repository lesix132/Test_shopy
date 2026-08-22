import XCTest
@testable import JobTrack

final class DashboardStatsTests: XCTestCase {

    private func offer(_ status: ApplicationStatus,
                       appliedDaysAgo: Int? = nil,
                       hasReply: Bool = false,
                       addedDaysAgo: Int = 0) -> JobOffer {
        let added = Calendar.current.date(byAdding: .day, value: -addedDaysAgo, to: .now)!
        let applied = appliedDaysAgo.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: .now)
        }
        return JobOffer(company: "ACME", dateAdded: added, status: status,
                        appliedAt: applied, hasReply: hasReply)
    }

    func testCountsAndPipeline() {
        let stats = DashboardStats(offers: [
            offer(.toProcess),
            offer(.applied, appliedDaysAgo: 2),
            offer(.interview, appliedDaysAgo: 10),
            offer(.accepted, appliedDaysAgo: 20, hasReply: true),
        ])
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.count(for: .toProcess), 1)
        XCTAssertEqual(stats.interviews, 1)
        // Everything past "toProcess" counts as applied.
        XCTAssertEqual(stats.applied, 3)
    }

    func testResponseRate() {
        let stats = DashboardStats(offers: [
            offer(.applied, appliedDaysAgo: 1),
            offer(.applied, appliedDaysAgo: 1, hasReply: true),
            offer(.interview, appliedDaysAgo: 1, hasReply: true),
            offer(.toProcess),
        ])
        // 2 replies over 3 applied → 67%.
        XCTAssertEqual(stats.responseRate, 67)
    }

    func testDueFollowUpsSortedSoonestFirst() {
        let stats = DashboardStats(offers: [
            offer(.applied, appliedDaysAgo: 30),   // very overdue
            offer(.applied, appliedDaysAgo: 8),    // just overdue
            offer(.applied, appliedDaysAgo: 2),    // not yet due
            offer(.applied, appliedDaysAgo: 40, hasReply: true), // replied → excluded
        ])
        XCTAssertEqual(stats.dueFollowUps.count, 2)
        let dates = stats.dueFollowUps.compactMap { $0.nextFollowUpDate() }
        XCTAssertEqual(dates, dates.sorted())
    }

    func testAddedLast7Days() {
        let stats = DashboardStats(offers: [
            offer(.toProcess, addedDaysAgo: 1),
            offer(.toProcess, addedDaysAgo: 3),
            offer(.toProcess, addedDaysAgo: 20),
        ])
        XCTAssertEqual(stats.addedLast7Days, 2)
    }
}
