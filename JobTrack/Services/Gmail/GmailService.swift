import Foundation

/// A file to attach to an outgoing message (e.g. the CV PDF).
struct EmailAttachment: Sendable {
    let filename: String
    let mimeType: String
    let data: Data
}

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

    /// Creates a Gmail draft (not sent) — the "brouillon". An optional
    /// attachment (e.g. the CV PDF) is added as a multipart part.
    func createDraft(to recipient: String, subject: String, body: String,
                     attachment: EmailAttachment? = nil) async throws {
        let token = try await oauth.validAccessToken()
        let raw = Self.makeRawMessage(
            to: recipient, from: oauth.connectedAddress, subject: subject, body: body,
            attachment: attachment)

        var request = URLRequest(url: URL(string: "\(AppConfig.gmailAPIBase)/drafts")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": ["raw": raw]])

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
        to: String, from: String?, subject: String, body: String,
        attachment: EmailAttachment? = nil
    ) -> String {
        var headers = ""
        if let from { headers += "From: \(from)\r\n" }
        headers += "To: \(to)\r\n"
        headers += "Subject: \(encodeHeader(subject))\r\n"
        headers += "MIME-Version: 1.0\r\n"

        let message: String
        if let attachment {
            let boundary = "JTBoundary-\(UUID().uuidString)"
            headers += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
            let bodyB64 = Data(body.utf8).base64EncodedString(
                options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
            let fileB64 = attachment.data.base64EncodedString(
                options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
            var parts = "--\(boundary)\r\n"
            parts += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
            parts += "Content-Transfer-Encoding: base64\r\n\r\n\(bodyB64)\r\n"
            parts += "--\(boundary)\r\n"
            parts += "Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"\r\n"
            parts += "Content-Disposition: attachment; filename=\"\(attachment.filename)\"\r\n"
            parts += "Content-Transfer-Encoding: base64\r\n\r\n\(fileB64)\r\n"
            parts += "--\(boundary)--"
            message = headers + parts
        } else {
            headers += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
            headers += "Content-Transfer-Encoding: base64\r\n\r\n"
            message = headers + Data(body.utf8).base64EncodedString()
        }
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
