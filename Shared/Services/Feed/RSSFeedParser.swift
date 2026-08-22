import Foundation

/// Minimal RSS 2.0 / Atom parser built on `XMLParser` (Foundation, available on
/// iOS and macOS). Extracts the fields JobTrack needs from `<item>`/`<entry>`.
enum RSSFeedParser {

    static func parse(data: Data, sourceName: String,
                      category: FeedCategory = .jobs) -> [FeedItem] {
        let delegate = Delegate(sourceName: sourceName, category: category)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    // MARK: - XML delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        let sourceName: String
        let category: FeedCategory
        private(set) var items: [FeedItem] = []

        private var current: [String: String] = [:]
        private var currentElement = ""
        private var buffer = ""
        private var insideItem = false
        /// Atom `<link href="...">` is an attribute, not element text.
        private var atomLinkFromAttribute: String?

        init(sourceName: String, category: FeedCategory) {
            self.sourceName = sourceName
            self.category = category
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String]) {
            let name = elementName.lowercased()
            if name == "item" || name == "entry" {
                insideItem = true
                current = [:]
                atomLinkFromAttribute = nil
            }
            currentElement = name
            buffer = ""
            // Atom links carry the URL in the href attribute.
            if insideItem, name == "link", let href = attributeDict["href"], !href.isEmpty {
                atomLinkFromAttribute = href
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                buffer += text
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.lowercased()

            if name == "item" || name == "entry" {
                items.append(makeItem())
                insideItem = false
                current = [:]
                buffer = ""
                return
            }

            guard insideItem else { buffer = ""; return }

            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title":                     current["title"] = value
            case "link":                      if current["link"] == nil { current["link"] = value }
            case "description", "summary",
                 "content", "content:encoded": if (current["description"] ?? "").isEmpty { current["description"] = value }
            case "pubdate", "published",
                 "updated", "dc:date":         if current["date"] == nil { current["date"] = value }
            case "guid", "id":                current["guid"] = value
            default:                          break
            }
            buffer = ""
        }

        // MARK: Build a FeedItem from the accumulated fields

        private func makeItem() -> FeedItem {
            let rawTitle = current["title"] ?? ""
            // News headlines aren't "Job at Company", so keep them intact and
            // don't try to extract a company from a colon/" at ".
            let (title, company): (String, String) = category == .news
                ? (rawTitle.strippingHTML, "")
                : splitTitleAndCompany(rawTitle)
            let link = (current["link"]?.nilIfBlank) ?? atomLinkFromAttribute
            let guid = current["guid"]?.nilIfBlank ?? link ?? rawTitle
            let summary = current["description"]?.strippingHTML ?? ""
            let date = current["date"].flatMap(RSSDate.parse)

            return FeedItem(
                id: "\(sourceName)#\(guid)",
                title: title,
                company: company,
                location: "",
                summary: summary,
                url: link,
                publishedAt: date,
                sourceName: sourceName,
                category: category
            )
        }

        /// Many job feeds encode the company in the title, e.g.
        /// "Company: Senior iOS Engineer" or "Senior iOS Engineer at Company".
        private func splitTitleAndCompany(_ raw: String) -> (title: String, company: String) {
            let title = raw.strippingHTML
            if let range = title.range(of: ": ") {
                let company = String(title[..<range.lowerBound]).trimmed
                let job = String(title[range.upperBound...]).trimmed
                if !company.isEmpty, !job.isEmpty { return (job, company) }
            }
            if let range = title.range(of: " at ", options: [.backwards]) {
                let job = String(title[..<range.lowerBound]).trimmed
                let company = String(title[range.upperBound...]).trimmed
                if !company.isEmpty, !job.isEmpty { return (job, company) }
            }
            return (title, "")
        }
    }
}

// MARK: - RFC-822 / ISO-8601 date parsing

private enum RSSDate {
    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let iso = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return rfc822.date(from: trimmed) ?? iso.date(from: trimmed)
    }
}

// MARK: - String helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfBlank: String? { trimmed.isEmpty ? nil : self }

    /// Crude HTML/entity stripping — enough to render feed summaries as plain text.
    var strippingHTML: String {
        let noTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return noTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
