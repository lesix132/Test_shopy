import XCTest
@testable import JobTrack

@MainActor
final class BrowserAutoScanTests: XCTestCase {

    func testLooksLikeJobPageDetectsOffers() {
        let offer = "Nous recrutons un ingénieur en CDI. Profil recherché : 3 ans "
            + "d'expérience, compétences en sûreté nucléaire. Télétravail partiel. "
            + String(repeating: "Détails du poste et missions. ", count: 20)
        XCTAssertTrue(WebViewModel.looksLikeJobPage(offer))
    }

    func testLooksLikeJobPageRejectsRandomPage() {
        let blog = "Bienvenue sur mon blog de cuisine. Voici une recette de tarte "
            + "aux pommes très simple à réaliser pour le dessert du dimanche."
        XCTAssertFalse(WebViewModel.looksLikeJobPage(blog))
    }

    func testLooksLikeJobPageRejectsTooShort() {
        XCTAssertFalse(WebViewModel.looksLikeJobPage("CDI poste emploi"))
    }

    func testMarkScannedIsOncePerURL() {
        let model = WebViewModel()
        let url = URL(string: "https://example.com/job/1")!
        XCTAssertTrue(model.markScannedIfNew(url))   // first time
        XCTAssertFalse(model.markScannedIfNew(url))  // already seen
        XCTAssertTrue(model.markScannedIfNew(URL(string: "https://example.com/job/2")!))
    }
}
