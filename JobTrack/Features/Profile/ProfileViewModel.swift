import Foundation
import Observation

/// Edits and persists the `CandidateProfile` (the AI's memory + geo preferences).
@MainActor
@Observable
final class ProfileViewModel {
    var profile: CandidateProfile
    var savedMessage: String?

    private let store: ProfileStore

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        self.profile = store.load()
    }

    func save() {
        store.save(profile)
        savedMessage = "Profil enregistré ✓"
    }

    func togglePreferred(_ region: FrenchRegion) {
        if let index = profile.preferredRegionsRaw.firstIndex(of: region.rawValue) {
            profile.preferredRegionsRaw.remove(at: index)
        } else {
            profile.preferredRegionsRaw.append(region.rawValue)
        }
    }

    func isPreferred(_ region: FrenchRegion) -> Bool {
        profile.preferredRegionsRaw.contains(region.rawValue)
    }
}
