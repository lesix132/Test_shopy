import XCTest
@testable import JobTrack

final class OfferListViewModelTests: XCTestCase {

    private func makeOffers() -> [JobOffer] {
        let a = JobOffer(title: "iOS Engineer", company: "ACME",
                         location: "Paris", descriptionText: "Swift SwiftUI",
                         dateAdded: Date(timeIntervalSince1970: 100),
                         status: .applied, tags: ["mobile"])
        a.matchScore = 90
        let b = JobOffer(title: "Backend Dev", company: "Globex",
                         location: "Lyon", descriptionText: "Go Kubernetes",
                         dateAdded: Date(timeIntervalSince1970: 200),
                         status: .toProcess, tags: ["backend"])
        b.matchScore = 40
        return [a, b]
    }

    func testSearchMatchesTitleAndDescription() {
        let vm = OfferListViewModel()
        vm.searchText = "swiftui"
        let result = vm.apply(to: makeOffers())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.company, "ACME")
    }

    func testStatusFilter() {
        let vm = OfferListViewModel()
        vm.statusFilter = .toProcess
        XCTAssertEqual(vm.apply(to: makeOffers()).map(\.company), ["Globex"])
    }

    func testTagFilter() {
        let vm = OfferListViewModel()
        vm.tagFilter = "mobile"
        XCTAssertEqual(vm.apply(to: makeOffers()).map(\.company), ["ACME"])
    }

    func testSortByMatchScore() {
        let vm = OfferListViewModel()
        vm.sort = .matchScore
        XCTAssertEqual(vm.apply(to: makeOffers()).map(\.company), ["ACME", "Globex"])
    }

    func testSortByDateNewest() {
        let vm = OfferListViewModel()
        vm.sort = .dateNewest
        XCTAssertEqual(vm.apply(to: makeOffers()).first?.company, "Globex")
    }

    func testCompaniesAndTagsAggregation() {
        let vm = OfferListViewModel()
        let offers = makeOffers()
        XCTAssertEqual(vm.companies(in: offers), ["ACME", "Globex"])
        XCTAssertEqual(vm.tags(in: offers), ["backend", "mobile"])
    }
}
