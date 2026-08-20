import XCTest
@testable import JobTrack

final class FollowUpLogicTests: XCTestCase {

    private func appliedOffer(daysAgo: Int, followUpAfterDays: Int = 7) -> JobOffer {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return JobOffer(
            title: "iOS", company: "ACME", status: .applied,
            appliedAt: date, followUpAfterDays: followUpAfterDays)
    }

    func testNeedsFollowUpWhenDelayElapsed() {
        let offer = appliedOffer(daysAgo: 8)
        XCTAssertTrue(offer.needsFollowUp())
    }

    func testNoFollowUpBeforeDelay() {
        let offer = appliedOffer(daysAgo: 3)
        XCTAssertFalse(offer.needsFollowUp())
    }

    func testNoFollowUpWhenReplied() {
        let offer = appliedOffer(daysAgo: 30)
        offer.hasReply = true
        XCTAssertFalse(offer.needsFollowUp())
    }

    func testNoFollowUpWhenNotApplied() {
        let offer = JobOffer(title: "iOS", company: "ACME", status: .toProcess)
        XCTAssertFalse(offer.needsFollowUp())
    }

    func testLastContactResetsTheClock() {
        let offer = appliedOffer(daysAgo: 30)
        offer.lastContactAt = .now
        XCTAssertFalse(offer.needsFollowUp())
    }

    func testNextFollowUpDateUsesAppliedDatePlusDelay() {
        let applied = Date(timeIntervalSince1970: 1_000_000)
        let offer = JobOffer(status: .applied, appliedAt: applied, followUpAfterDays: 5)
        let expected = applied.addingTimeInterval(5 * 86_400)
        XCTAssertEqual(offer.nextFollowUpDate(), expected)
    }
}
