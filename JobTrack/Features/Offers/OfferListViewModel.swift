import Foundation
import Observation

/// Sort options for the offers list.
enum OfferSort: String, CaseIterable, Identifiable {
    case dateNewest
    case dateOldest
    case company
    case matchScore   // pertinence

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateNewest: return "Date (récent)"
        case .dateOldest: return "Date (ancien)"
        case .company:    return "Entreprise"
        case .matchScore: return "Pertinence"
        }
    }
}

/// Holds the list's filter/search/sort state and applies it to offers.
/// Pure logic, no SwiftUI — easy to unit-test.
@Observable
final class OfferListViewModel {
    var searchText = ""
    var statusFilter: ApplicationStatus?
    var companyFilter: String?
    var tagFilter: String?
    var sort: OfferSort = .dateNewest

    /// Distinct companies present in the data (for the filter menu).
    func companies(in offers: [JobOffer]) -> [String] {
        Set(offers.map(\.company))
            .subtracting([""])
            .sorted()
    }

    /// Distinct tags present in the data.
    func tags(in offers: [JobOffer]) -> [String] {
        Set(offers.flatMap(\.tags)).sorted()
    }

    /// Applies search + filters + sort.
    func apply(to offers: [JobOffer]) -> [JobOffer] {
        var result = offers

        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        if let companyFilter {
            result = result.filter { $0.company == companyFilter }
        }
        if let tagFilter {
            result = result.filter { $0.tags.contains(tagFilter) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { offer in
                offer.title.lowercased().contains(query)
                    || offer.company.lowercased().contains(query)
                    || offer.location.lowercased().contains(query)
                    || offer.descriptionText.lowercased().contains(query)
                    || offer.notes.lowercased().contains(query)
                    || offer.tags.contains { $0.lowercased().contains(query) }
            }
        }

        switch sort {
        case .dateNewest:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .dateOldest:
            result.sort { $0.dateAdded < $1.dateAdded }
        case .company:
            result.sort { $0.company.localizedCaseInsensitiveCompare($1.company) == .orderedAscending }
        case .matchScore:
            result.sort { ($0.matchScore ?? -1) > ($1.matchScore ?? -1) }
        }
        return result
    }

    var hasActiveFilters: Bool {
        statusFilter != nil || companyFilter != nil || tagFilter != nil
    }

    func clearFilters() {
        statusFilter = nil
        companyFilter = nil
        tagFilter = nil
    }
}
