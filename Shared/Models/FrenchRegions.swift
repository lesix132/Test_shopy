import Foundation

/// French administrative regions (plus remote), used to tag and filter offers.
enum FrenchRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case idf = "Île-de-France"
    case ara = "Auvergne-Rhône-Alpes"
    case naq = "Nouvelle-Aquitaine"
    case occ = "Occitanie"
    case hdf = "Hauts-de-France"
    case ges = "Grand Est"
    case pdl = "Pays de la Loire"
    case bre = "Bretagne"
    case nor = "Normandie"
    case bfc = "Bourgogne-Franche-Comté"
    case cvl = "Centre-Val de Loire"
    case pac = "Provence-Alpes-Côte d'Azur"
    case cor = "Corse"
    case dom = "Outre-mer"
    case remote = "Télétravail"

    var id: String { rawValue }

    /// Major cities / keywords that map to each region (lowercased, no accents).
    private static let cityMap: [(FrenchRegion, [String])] = [
        (.idf, ["paris", "ile-de-france", "ile de france", "boulogne", "nanterre",
                "versailles", "saint-denis", "creteil", "montreuil", "la defense",
                "issy", "levallois", "92", "75", "93", "94", "91", "95", "78", "77"]),
        (.ara, ["lyon", "grenoble", "saint-etienne", "clermont-ferrand", "annecy",
                "villeurbanne", "chambery", "valence", "rhone-alpes", "auvergne"]),
        (.naq, ["bordeaux", "limoges", "poitiers", "la rochelle", "pau", "bayonne",
                "angouleme", "niort", "nouvelle-aquitaine", "aquitaine"]),
        (.occ, ["toulouse", "montpellier", "nimes", "perpignan", "beziers", "albi",
                "carcassonne", "occitanie", "tarbes"]),
        (.hdf, ["lille", "amiens", "roubaix", "tourcoing", "dunkerque", "calais",
                "arras", "valenciennes", "hauts-de-france", "nord-pas"]),
        (.ges, ["strasbourg", "nancy", "metz", "reims", "mulhouse", "colmar",
                "troyes", "grand est", "alsace", "lorraine", "champagne"]),
        (.pdl, ["nantes", "angers", "le mans", "saint-nazaire", "la roche-sur-yon",
                "cholet", "pays de la loire"]),
        (.bre, ["rennes", "brest", "quimper", "lorient", "vannes", "saint-malo",
                "bretagne"]),
        (.nor, ["rouen", "caen", "le havre", "cherbourg", "evreux", "normandie"]),
        (.bfc, ["dijon", "besancon", "belfort", "chalon", "nevers", "auxerre",
                "bourgogne", "franche-comte"]),
        (.cvl, ["orleans", "tours", "bourges", "chartres", "blois", "chateauroux",
                "centre-val de loire"]),
        (.pac, ["marseille", "nice", "toulon", "aix-en-provence", "avignon", "cannes",
                "antibes", "provence", "cote d'azur", "cote d azur", "paca"]),
        (.cor, ["ajaccio", "bastia", "corse", "corsica"]),
        (.dom, ["guadeloupe", "martinique", "guyane", "reunion", "mayotte",
                "outre-mer", "outremer"]),
    ]

    private static let remoteKeywords = ["remote", "teletravail", "télétravail",
                                         "télé-travail", "full remote", "100% remote",
                                         "hybride", "distanciel"]

    /// Detects the region from a free-form location string, if possible.
    static func detect(from location: String) -> FrenchRegion? {
        let normalized = location.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        for (region, keys) in cityMap {
            if keys.contains(where: { normalized.contains($0) }) { return region }
        }
        if remoteKeywords.contains(where: { normalized.contains($0) }) { return .remote }
        return nil
    }

    /// Whether a location looks France-based (a known FR place, "france", or remote).
    static func isLikelyFrance(_ location: String) -> Bool {
        let normalized = location.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        if normalized.contains("france") { return true }
        return detect(from: location) != nil
    }
}
