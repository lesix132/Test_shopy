import Foundation

/// Sends email through the connected Gmail account and checks for replies.
/// Uses `GoogleOAuthService` for tokens. The user connects their own account;
/// nothing is sent without an explicit action.
@MainActor
final class GmailService {

    private let oauth: GoogleOAuthService
    private let session: URLSession

    init(oauth: GoogleOAuthService, session: URLSession = .shared) {
        self.oauth = oauth
        self.session = session
    }

    var isConnected: Bool { oauth.isConnected }
    var address: String? { oauth.connectedAddress }

    // MARK: Send

    func send(to recipient: String, subject: String, body: String) async throws {
        let token = try await oauth.validAccessToken()
        let raw = Self.makeRawMessage(
            to: recipient, from: oauth.connectedAddress, subject: subject, body: body)

        var request = URLRequest(url: URL(string: "\(AppConfig.gmailAPIBase)/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["raw": raw])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GmailError.sendFailed(String(data: data, encoding: .utf8) ?? "erreur")
            }
        } catch let error as GmailError {
            throw error
        } catch {
            throw GmailError.network(error.localizedDescription)
        }
    }

    // MARK: Reply detection

    /// Returns true if the inbox contains a message from the offer's contact
    /// (or company) since the application date — a likely reply.
    func hasReply(from contactEmail: String?, company: String, since: Date?) async throws -> Bool {
        let token = try await oauth.validAccessToken()

        var query = "in:inbox"
        if let contactEmail, !contactEmail.isEmpty {
            query += " from:\(contactEmail)"
        } else if !company.isEmpty {
            query += " from:\(company)"
        } else {
            return false
        }
        if let since {
            let days = max(1, Int(-since.timeIntervalSinceNow / 86_400) + 1)
            query += " newer_than:\(days)d"
        }

        var components = URLComponents(string: "\(AppConfig.gmailAPIBase)/messages")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "maxResults", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GmailError.network("liste des messages indisponible")
        }
        let list = try JSONDecoder().decode(MessageList.self, from: data)
        return (list.resultSizeEstimate ?? 0) > 0
    }

    // MARK: RFC 822

    private static func makeRawMessage(
        to: String, from: String?, subject: String, body: String
    ) -> String {
        var headers = ""
        if let from { headers += "From: \(from)\r\n" }
        headers += "To: \(to)\r\n"
        headers += "Subject: \(encodeHeader(subject))\r\n"
        headers += "MIME-Version: 1.0\r\n"
        headers += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
        headers += "Content-Transfer-Encoding: base64\r\n\r\n"

        let encodedBody = Data(body.utf8).base64EncodedString()
        let message = headers + encodedBody
        return Data(message.utf8).base64URLEncodedString()
    }

    /// MIME-encode a header value so non-ASCII subjects survive.
    private static func encodeHeader(_ value: String) -> String {
        if value.allSatisfy(\.isASCII) { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private struct MessageList: Decodable {
        let resultSizeEstimate: Int?
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
