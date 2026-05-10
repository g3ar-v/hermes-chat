import Foundation

// MARK: - Honcho Memory Service

/// Fetches user context from the Honcho API for Memory mode.
/// Honcho runs locally on port 8000.
public actor HonchoMemoryService {
    public static let shared = HonchoMemoryService()

    private let baseURL = URL(string: "http://localhost:8000/v1")!
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        session = URLSession(configuration: cfg)
    }

    // MARK: - Fetch Context

    /// Fetches relevant context for the current user from Honcho.
    /// Returns a string suitable for prepending to a prompt, or nil if no context.
    public func fetchContext(peerId: String = "user") async throws -> String? {
        let url = baseURL.appendingPathComponent("peers/\(peerId)/context")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 404 || http.statusCode == 204 {
            return nil // No context yet
        }

        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw HonchoError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Honcho returns context as a string in the "context" or "content" field
        if let context = json["context"] as? String, !context.isEmpty {
            return context
        }
        if let content = json["content"] as? String, !content.isEmpty {
            return content
        }

        return nil
    }

    // MARK: - Peer Info

    public struct PeerInfo: Sendable {
        public let id: String
        public let name: String
        public let email: String?
    }

    public func fetchPeerInfo(peerId: String = "user") async throws -> PeerInfo? {
        let url = baseURL.appendingPathComponent("peers/\(peerId)")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return PeerInfo(
            id: json["id"] as? String ?? peerId,
            name: json["name"] as? String ?? "User",
            email: json["email"] as? String
        )
    }
}

// MARK: - Errors

public enum HonchoError: Error, LocalizedError {
    case httpError(Int)
    case decodingError

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Honcho returned HTTP \(code)"
        case .decodingError: return "Failed to decode Honcho response"
        }
    }
}