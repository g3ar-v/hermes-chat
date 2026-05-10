import Foundation

// MARK: - Chat Message

public struct ChatMessage: Identifiable, Sendable {
    public let id: String
    public let role: Role
    public let content: String
    public let timestamp: Date
    public let isGenerating: Bool
    public let thinking: String?
    public let toolName: String?
    public let toolSummary: String?

    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        timestamp: Date = Date(),
        isGenerating: Bool = false,
        thinking: String? = nil,
        toolName: String? = nil,
        toolSummary: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isGenerating = isGenerating
        self.thinking = thinking
        self.toolName = toolName
        self.toolSummary = toolSummary
    }
}

// MARK: - Loading State

public enum LoadingState: Equatable, Sendable {
    case idle
    case loading
    case error(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}