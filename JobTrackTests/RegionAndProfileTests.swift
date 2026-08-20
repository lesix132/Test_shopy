import XCTest
@testable import JobTrack

final class RegionAndProfileTests: XCTestCase {

    func testDetectRegionFromCity() {
        XCTAssertEqual(FrenchRegion.detect(from: "Paris, France"), .idf)
        XCTAssertEqual(FrenchRegion.detect(from: "Lyon"), .ara)
        XCTAssertEqual(FrenchRegion.detect(from: "Bordeaux (33)"), .naq)
        XCTAssertEqual(FrenchRegion.detect(from: "Télétravail"), .remote)
    }

    func testDetectRegionIsDiacriticInsensitive() {
        XCTAssertEqual(FrenchRegion.detect(from: "TELETRAVAIL"), .remote)
        XCTAssertEqual(FrenchRegion.detect(from: "marseille"), .pac)
    }

    func testUnknownLocationReturnsNil() {
        XCTAssertNil(FrenchRegion.detect(from: "London, UK"))
        XCTAssertNil(FrenchRegion.detect(from: ""))
    }

    func testIsLikelyFrance() {
        XCTAssertTrue(FrenchRegion.isLikelyFrance("Nantes"))
        XCTAssertTrue(FrenchRegion.isLikelyFrance("Remote - France"))
        XCTAssertFalse(FrenchRegion.isLikelyFrance("Berlin, Germany"))
    }

    func testProfilePromptContextIncludesIdentity() {
        var profile = CandidateProfile()
        profile.fullName = "Jean Dupont"
        profile.email = "jean@example.com"
        profile.headline = "Ingénieur nucléaire"
        let context = profile.promptContext
        XCTAssertTrue(context.contains("Jean Dupont"))
        XCTAssertTrue(context.contains("jean@example.com"))
        XCTAssertTrue(context.contains("Ingénieur nucléaire"))
    }

    func testEmptyProfileHasEmptyContext() {
        XCTAssertTrue(CandidateProfile().promptContext.isEmpty)
        XCTAssertFalse(CandidateProfile().isComplete)
    }
}
