import Foundation
import Observation
import AuthenticationServices

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

    /// Pre-fills the profile from fields extracted from a CV (non-empty wins).
    func applyExtracted(_ e: ExtractedProfile) {
        if !e.fullName.isEmpty { profile.fullName = e.fullName }
        if !e.email.isEmpty { profile.email = e.email }
        if !e.phone.isEmpty { profile.phone = e.phone }
        if !e.headline.isEmpty { profile.headline = e.headline }
        if !e.city.isEmpty { profile.city = e.city }
        if !e.summary.isEmpty { profile.summary = e.summary }
        save()
        savedMessage = "Profil pré-rempli depuis le CV ✓ Complète si besoin."
    }

    // MARK: Sign in with Apple

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: name)
                if !formatted.isEmpty { profile.fullName = formatted }
            }
            if let email = credential.email, !email.isEmpty {
                profile.email = email
            }
            save()
            savedMessage = "Connecté avec Apple ✓"
        case .failure:
            savedMessage = "Connexion Apple annulée."
        }
    }

    /// Fill the email from a connected Google/Gmail account.
    func fillEmail(_ email: String?) {
        guard let email, !email.isEmpty else { return }
        profile.email = email
        save()
        savedMessage = "Connecté avec Google ✓"
    }
}
