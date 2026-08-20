import XCTest
@testable import JobTrack

/// Test double for `JobFeedService`.
final class MockJobFeedService: JobFeedService {
    var result: FeedFetchResult
    private(set) var fetchCallCount = 0

    init(result: FeedFetchResult) { self.result = result }

    func fetch(from sources: [FeedSource]) async -> FeedFetchResult {
        fetchCallCount += 1
        return result
    }
}

@MainActor
final class FeedViewModelTests: XCTestCase {

    private func makeItems() -> [FeedItem] {
        [
            FeedItem(id: "s#1", title: "iOS Engineer", company: "ACME",
                     location: "Remote", summary: "Swift SwiftUI role",
                     url: "https://example.com/1",
                     publishedAt: Date(timeIntervalSince1970: 200), sourceName: "Src"),
            FeedItem(id: "s#2", title: "Backend Dev", company: "Globex",
                     location: "Lyon", summary: "Go role",
                     url: "https://example.com/2",
                     publishedAt: Date(timeIntervalSince1970: 100), sourceName: "Src"),
        ]
    }

    func testRefreshPopulatesItems() async {
        let service = MockJobFeedService(result: FeedFetchResult(items: makeItems(), failures: []))
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        await vm.refresh()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testKeywordFiltersItems() async {
        let service = MockJobFeedService(result: FeedFetchResult(items: makeItems(), failures: []))
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        await vm.refresh()
        vm.keyword = "swiftui"
        XCTAssertEqual(vm.filteredItems.map(\.company), ["ACME"])
    }

    func testMakeOfferMapsFields() async {
        let service = MockJobFeedService(result: .empty)
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        let item = makeItems()[0]
        let offer = vm.makeOffer(from: item)
        XCTAssertEqual(offer.title, "iOS Engineer")
        XCTAssertEqual(offer.company, "ACME")
        XCTAssertEqual(offer.sourceURL, "https://example.com/1")
        XCTAssertFalse(offer.needsParsing)
        XCTAssertTrue(offer.tags.contains("Src"))
        // "Remote" location → region tag "Télétravail" is added automatically.
        XCTAssertTrue(offer.tags.contains(FrenchRegion.remote.rawValue))
    }

    func testLoadIfNeededFetchesOnlyOnce() async {
        let service = MockJobFeedService(result: .empty)
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()
        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testAnalyzeEnrichesSavedOffer() async {
        let service = MockJobFeedService(result: FeedFetchResult(items: makeItems(), failures: []))
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        await vm.refresh()
        let item = vm.items[0]
        await vm.analyze(item, resumeText: "CV")
        XCTAssertEqual(vm.analyses[item.id]?.matchScore, 80)

        let offer = vm.makeOffer(from: item)
        XCTAssertEqual(offer.matchScore, 80)
        XCTAssertTrue(offer.tags.contains("swift"))
    }

    func testTranslateIsCached() async {
        let service = MockJobFeedService(result: FeedFetchResult(items: makeItems(), failures: []))
        let vm = FeedViewModel(service: service, claude: MockClaudeService())
        await vm.refresh()
        let item = vm.items[0]
        await vm.translate(item)
        XCTAssertEqual(vm.translations[item.id]?.title, "Ingénieur")
    }
}
