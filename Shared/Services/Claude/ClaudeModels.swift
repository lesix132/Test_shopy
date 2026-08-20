import Foundation

// MARK: - Request DTOs (Anthropic Messages API)

struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case temperature
    }

    struct Message: Encodable {
        let role: String   // "user" | "assistant"
        let content: String
    }
}

// MARK: - Response DTOs

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    /// Concatenated text from all text blocks.
    var text: String {
        content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }
}

/// Error envelope returned by the API on non-2xx responses.
struct ClaudeAPIErrorEnvelope: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let type: String
        let message: String
    }
}

// MARK: - Domain result for offer parsing

/// Structured offer fields extracted by Claude from raw text.
struct ParsedOffer: Codable, Equatable {
    var title: String
    var company: String
    var location: String
    var description: String
}
