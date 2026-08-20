import XCTest
import SwiftData
@testable import JobTrack

@MainActor
final class AddOfferViewModelTests: XCTestCase {

    func testParseSuccessPopulatesFields() async {
        let mock = MockClaudeService()
        mock.parseResult = .success(
            ParsedOffer(title: "Data Engineer", company: "Globex",
                        location: "Remote", description: "Python, dbt")
        )
        let vm = AddOfferViewModel(claude: mock)
        vm.rawText = "Un long texte d'offre collé depuis LinkedIn…"

        await vm.parseWithClaude()

        XCTAssertEqual(vm.title, "Data Engineer")
        XCTAssertEqual(vm.company, "Globex")
        XCTAssertEqual(vm.location, "Remote")
        XCTAssertEqual(vm.description(), "Python, dbt")
        XCTAssertTrue(vm.hasContent)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(mock.parseCallCount, 1)
    }

    func testParseFailureFallsBackToRawText() async {
        let mock = MockClaudeService()
        mock.parseResult = .failure(ClaudeError.invalidAPIKey)
        let vm = AddOfferViewModel(claude: mock)
        vm.rawText = "Texte brut de secours"

        await vm.parseWithClaude()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.hasContent)
        XCTAssertEqual(vm.descriptionText, "Texte brut de secours")
    }

    func testSaveInsertsOffer() throws {
        let mock = MockClaudeService()
        let vm = AddOfferViewModel(claude: mock)
        vm.title = "QA Engineer"
        vm.descriptionText = "Tests everywhere"
        vm.hasContent = true

        let container = try ModelContainer(
            for: JobOffer.self, Resume.self, CoverLetter.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        vm.save(into: context)

        let all = try context.fetch(FetchDescriptor<JobOffer>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "QA Engineer")
        XCTAssertFalse(all.first?.needsParsing ?? true)
    }
}

private extension AddOfferViewModel {
    /// Test helper mirroring the bound `descriptionText`.
    func description() -> String { descriptionText }
}
