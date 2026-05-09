import Foundation
import Combine

// MARK: - Chat View Model
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    // MARK: - Finalized Messages
    @Published public private(set) var messages: [ChatMessage] = []

    // MARK: - Live Streaming State (transient, not in messages until finalized)
    // Non-published: update only when finalizing or explicitly published
    public var liveContent: String = ""
    public var liveThinking: String?
    public var liveToolName: String?
    public var liveToolSummary: String?

    // MARK: - UI State
    @Published public var loadingState: LoadingState = .idle
    @Published public var isConnected: Bool = false
    @Published public var statusText: String = "Connecting…"

    @Published public var chatMode: ChatMode = .stateless {
        didSet { resetConversation() }
    }

    // MARK: - Private
    private var isGenerating = false

    // MARK: - Init

    public init() {}

    // MARK: - Gateway Lifecycle

    public func connect() async {
        do {
            try await GatewayClient.shared.start()
            _ = try await GatewayClient.shared.createSession()
            statusText = "Connected"
            isConnected = true

            GatewayClient.shared.addEventHandler { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleEvent(event)
                }
            }

            messages = [
                ChatMessage(
                    role: .assistant,
                    content: "Hermes is ready. Ask me anything.",
                    timestamp: Date()
                )
            ]
        } catch {
            statusText = "Gateway error: \(error.localizedDescription)"
            loadingState = .error(error.localizedDescription)
        }
    }

    public func disconnect() {
        GatewayClient.shared.stop()
        isConnected = false
        currentSessionId = nil
    }

    // MARK: - Send Message

    public func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isConnected, let sessionId = currentSessionId else { return }

        // Append user message
        messages.append(ChatMessage(
            role: .user,
            content: text,
            timestamp: Date()
        ))

        // Reset live state
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .loading
        isGenerating = true

        // Build prompt
        var prompt = text
        if chatMode == .memory {
            do {
                if let context = try await HonchoMemoryService.shared.fetchContext() {
                    prompt = """
                    [CONTEXT FROM MEMORY]
                    \(context)

                    [USER MESSAGE]
                    \(text)
                    """
                }
            } catch {
                // Non-fatal
            }
        }

        do {
            try await GatewayClient.shared.submitPrompt(sessionId: sessionId, text: prompt)
        } catch {
            handleError(error)
        }
    }

    public func stopGenerating() async {
        guard isGenerating, let sessionId = currentSessionId else { return }
        isGenerating = false
        loadingState = .idle

        // Finalize any live content
        if !liveContent.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: liveContent,
                timestamp: Date()
            ))
        }

        // Clear live state
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil

        try? await GatewayClient.shared.interrupt(sessionId: sessionId)
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: GatewayEvent) {
        switch event {
        case .thinkingDelta(let text):
            liveThinking = text
            // Also append to liveContent so nothing is lost
            liveContent += text

        case .reasoningAvailable(let text):
            liveThinking = text

        case .reasoningDelta:
            break

        case .messageStart:
            liveThinking = nil
            liveToolName = nil
            liveToolSummary = nil

        case .toolStart(_, let name, let context):
            liveToolName = name
            liveToolSummary = context

        case .toolProgress(_, _, let preview):
            if let preview = preview {
                liveToolSummary = preview
            }

        case .toolComplete:
            liveToolName = nil
            liveToolSummary = nil

        case .statusUpdate(_, let text):
            statusText = text

        case .sessionInfo:
            break

        case .messageComplete(let text, _):
            finalizeResponse(text)

        case .gatewayReady:
            statusText = "Connected"
            isConnected = true

        case .error(let msg):
            // Treat as a final message
            finalizeResponse("Error: \(msg)")
        }
    }

    // Called by external monitor when response is fully done
    public func finalizeResponse(_ finalContent: String) {
        messages.append(ChatMessage(
            role: .assistant,
            content: finalContent,
            timestamp: Date()
        ))
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .idle
        isGenerating = false
    }

    private func handleError(_ error: Error) {
        messages.append(ChatMessage(
            role: .assistant,
            content: "Error: \(error.localizedDescription)",
            timestamp: Date()
        ))
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .error(error.localizedDescription)
        isGenerating = false
    }

    private var currentSessionId: String?

    // MARK: - Helpers

    private func resetConversation() {
        messages = []
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .idle
        isGenerating = false

        Task {
            if isConnected {
                do {
                    let result = try await GatewayClient.shared.createSession()
                    currentSessionId = result.sessionId
                    messages = [
                        ChatMessage(
                            role: .assistant,
                            content: "Mode switched to \(chatMode.rawValue). Ready.",
                            timestamp: Date()
                        )
                    ]
                } catch {
                    handleError(error)
                }
            }
        }
    }
}
