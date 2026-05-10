import Foundation

// MARK: - Gateway Transcript Messages

public struct GatewayTranscriptMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: Role
    public let text: String
    public let context: String?

    public enum Role: String, Equatable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public init(id: String = UUID().uuidString, role: Role, text: String, context: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
    }
}

// MARK: - Session Info

public struct GatewaySessionInfo: Equatable, Sendable {
    public let sessionId: String
    public let startedAt: Int
    public let messageCount: Int
    public let model: String?
    public let provider: String?
    public let title: String

    public init(sessionId: String, startedAt: Int, messageCount: Int, model: String?, provider: String?, title: String) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.messageCount = messageCount
        self.model = model
        self.provider = provider
        self.title = title
    }
}

// MARK: - Gateway Events

public enum GatewayEvent: Equatable, Sendable {
    case thinkingDelta(String)
    case reasoningDelta(String)
    case reasoningAvailable(String)
    case messageStart
    case messageDelta(String)
    case toolStart(id: String, name: String, context: String?)
    case toolProgress(id: String, name: String, preview: String?)
    case toolComplete(id: String, name: String, summary: String?)
    case statusUpdate(kind: String, text: String)
    case sessionInfo(GatewaySessionInfo)
    case messageComplete(text: String, reasoning: String?)
    case gatewayReady
    case error(String)

    public static func from(type: String, payload: [String: Any]?) -> GatewayEvent? {
        switch type {
        case "thinking.delta":
            return .thinkingDelta(payload?["text"] as? String ?? "")
        case "reasoning.delta":
            return .reasoningDelta(payload?["text"] as? String ?? "")
        case "reasoning.available":
            return .reasoningAvailable(payload?["text"] as? String ?? "")
        case "message.start":
            return .messageStart
        case "message.delta":
            return .messageDelta(payload?["text"] as? String ?? "")
        case "tool.start":
            return .toolStart(
                id: payload?["tool_id"] as? String ?? "",
                name: payload?["name"] as? String ?? "",
                context: payload?["context"] as? String
            )
        case "tool.progress":
            return .toolProgress(
                id: (payload?["name"] as? [String: Any])?["name"] as? String ?? "",
                name: payload?["name"] as? String ?? "",
                preview: payload?["preview"] as? String
            )
        case "tool.complete":
            let p = payload
            return .toolComplete(
                id: (p?["name"] as? [String: Any])?["tool_id"] as? String ?? "",
                name: p?["name"] as? String ?? "",
                summary: p?["summary"] as? String
            )
        case "status.update":
            return .statusUpdate(
                kind: payload?["kind"] as? String ?? "",
                text: payload?["text"] as? String ?? ""
            )
        case "session.info":
            guard let info = payload else { return nil }
            return .sessionInfo(GatewaySessionInfo(
                sessionId: info["session_id"] as? String ?? "",
                startedAt: info["started_at"] as? Int ?? 0,
                messageCount: info["message_count"] as? Int ?? 0,
                model: info["model"] as? String,
                provider: info["provider"] as? String,
                title: info["title"] as? String ?? ""
            ))
        case "message.complete":
            let reasoning = (payload as? [String: Any])?["reasoning"] as? String
            let text = (payload as? [String: Any])?["text"] as? String ?? ""
            return .messageComplete(text: text, reasoning: reasoning)
        case "gateway.ready":
            return .gatewayReady
        case "error":
            return .error(payload?["message"] as? String ?? "Unknown error")
        default:
            return nil
        }
    }
}

// MARK: - Chat Mode

public enum ChatMode: String, CaseIterable, Identifiable {
    case stateless = "Stateless"
    case memory = "Memory"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .stateless: return "brain"
        case .memory: return "brain.head.profile"
        }
    }

    public var description: String {
        switch self {
        case .stateless: return "No memory — each message is independent"
        case .memory: return "Context-enriched via Honcho memory"
        }
    }
}

// MARK: - App Mode State

@Observable
public final class AppState {
    public var chatMode: ChatMode = .stateless
    public var isGatewayReady: Bool = false
    public var isConnected: Bool = false

    public init() {}
}