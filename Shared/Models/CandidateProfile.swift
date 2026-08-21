import Foundation

/// The user's job-search profile — the "memory" the AI reuses to personalize
/// applications and follow-ups, and the geographic preferences used to filter
/// the feed. Stored as a single Codable value (App Group UserDefaults).
struct CandidateProfile: Codable, Sendable, Equatable {
    var fullName = ""
    var email = ""
    var phone = ""
    var linkedIn = ""
    var city = ""
    var regionRaw = ""
    var headline = ""          // titre professionnel
    var summary = ""           // accroche / points forts
    var targetKeywords = ""    // mots-clés de recherche
    var franceOnly = true
    var preferredRegionsRaw: [String] = []

    var region: FrenchRegion? {
        get { FrenchRegion(rawValue: regionRaw) }
        set { regionRaw = newValue?.rawValue ?? "" }
    }

    var preferredRegions: [FrenchRegion] {
        preferredRegionsRaw.compactMap(FrenchRegion.init(rawValue:))
    }

    /// True once the essentials are filled in.
    var isComplete: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Compact identity block Claude uses to sign/personalize emails & letters.
    var promptContext: String {
        var lines: [String] = []
        if !fullName.isEmpty { lines.append("Nom : \(fullName)") }
        if !headline.isEmpty { lines.append("Titre : \(headline)") }
        if !email.isEmpty { lines.append("Email : \(email)") }
        if !phone.isEmpty { lines.append("Téléphone : \(phone)") }
        if !linkedIn.isEmpty { lines.append("LinkedIn : \(linkedIn)") }
        if !city.isEmpty || !regionRaw.isEmpty {
            lines.append("Localisation : \([city, regionRaw].filter { !$0.isEmpty }.joined(separator: ", "))")
        }
        if !summary.isEmpty { lines.append("Points forts : \(summary)") }
        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }
}

/// Fields extracted by Claude from a CV, used to pre-fill the profile.
struct ExtractedProfile: Sendable, Codable {
    var fullName = ""
    var email = ""
    var phone = ""
    var headline = ""
    var city = ""
    var summary = ""
}

/// Persists the single `CandidateProfile` in the App Group `UserDefaults`.
struct ProfileStore {
    private let key = "candidate.profile.v1"
    private let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    func load() -> CandidateProfile {
        guard let data = defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(CandidateProfile.self, from: data)
        else { return CandidateProfile() }
        return profile
    }

    func save(_ profile: CandidateProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: key)
        }
    }
}
