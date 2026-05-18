// MARK: - Chat View Model
import Combine
import Foundation

// MARK: - Debug Toggle
// Set to true to enable console logging for events and state transitions
private let debugLogs = false

@MainActor
public final class ChatViewModel: ObservableObject {
    // MARK: - Finalized Messages
    @Published public private(set) var messages: [ChatMessage] = []

    // MARK: - Live Streaming State (transient, not in messages until finalized)
    // Non-published: update only when finalizing or explicitly published
    @Published public var liveContent: String = ""
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

    // Push-style synthesized status for UI
    @Published public var currentStatus: String? = nil

    // Current model/provider info from gateway session
    @Published public var modelLabel: String? = nil
   
    // Current Hermes Profile used in chat
    @Published public var chatProfile: String? = nil

    // MARK: - Private
    private var isGenerating = false

    // MARK: - Init

    public init() {}

    // MARK: - Gateway Lifecycle

    public func connect() async {
        do {
            let profileName = ProfileService.shared.activeProfileName
            try await GatewayClient.shared.start(profile: profileName)
            chatProfile = profileName
            let session = try await GatewayClient.shared.createSession()
            currentSessionId = session.sessionId
            statusText = "Connected"
            isConnected = true

            GatewayClient.shared.addEventHandler { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleEvent(event)
                }
            }

            // Start with no messages. Message view should only show assistant responses to prompts.
            messages = []
            refreshCurrentStatus()
        } catch {
            statusText = "Gateway error: \(error.localizedDescription)"
            loadingState = .error(error.localizedDescription)
            refreshCurrentStatus()
        }
    }

    public func disconnect() {
        GatewayClient.shared.stop()
        isConnected = false
        currentSessionId = nil
        refreshCurrentStatus()
    }

    // MARK: - Send Message

    public func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isConnected, let sessionId = currentSessionId else { return }

        // Clear previous assistant response — message view should only show the current assistant response
        messages = []

        // Reset live state
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .loading
        isGenerating = true
        refreshCurrentStatus()

        // Build prompt
        var prompt = text
//        if chatMode == .memory {
//            do {
//                if let context = try await HonchoMemoryService.shared.fetchContext() {
//                    prompt = """
//                        [CONTEXT FROM MEMORY]
//                        \(context)
//
//                        [USER MESSAGE]
//                        \(text)
//                        """
//                }
//            } catch {
//                // Non-fatal
//            }
//        }

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
            // Replace any previous content with the finalized assistant response
            messages = [
                ChatMessage(
                    role: .assistant,
                    content: liveContent,
                    timestamp: Date()
                )
            ]
        }

        // Clear live state
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil

        try? await GatewayClient.shared.interrupt(sessionId: sessionId)
        refreshCurrentStatus()
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: GatewayEvent) {
        switch event {
        case .messageDelta(let text):
            // Append streaming assistant text to liveContent so the UI can show it
            liveContent += text
            if debugLogs {
                print("[DEBUG] messageDelta -> liveContent length: \(liveContent.count), isEmpty: \(liveContent.isEmpty), isWhitespaceOnly: \(liveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
            }
            return
        case .thinkingDelta(let text):
            liveThinking = text
            if debugLogs { print("[DEBUG] thinkingDelta -> liveContent: \(liveContent.count), liveThinking: \(liveThinking?.count ?? 0)") }
            // Also append to liveContent so nothing is lost
//            liveContent += text

        case .reasoningAvailable(let text):
            liveThinking = text
            if debugLogs { print("[DEBUG] reasoningAvailable -> liveContent: \(liveContent.count), liveThinking: \(liveThinking?.count ?? 0)") }

        case .reasoningDelta:
            break

        case .messageStart:
            liveThinking = nil
            liveToolName = nil
            liveToolSummary = nil

        case .toolStart(_, let name, let context):
            liveToolName = name
            liveToolSummary = context
            if debugLogs { print("[DEBUG] toolStart: \(name), summary: \(context ?? "nil")") }

        case .toolProgress(_, _, let preview):
            if let preview = preview {
                liveToolSummary = preview
            }

        case .toolComplete:
            liveToolName = nil
            liveToolSummary = nil

        case .statusUpdate(_, let text):
            statusText = text

        case .sessionInfo(let info):
            if let model = info.model {
                modelLabel = info.provider.map { "\(model) @ \($0)" } ?? model
            }
            break

        case .messageComplete(let text, _):
            if debugLogs { print("[DEBUG] messageComplete, text length: \(text.count)") }
            finalizeResponse(text)

        case .gatewayReady:
            statusText = "Gateway Connected"
            isConnected = true

        case .error(let msg):
            // Treat as a final message
            finalizeResponse("Error: \(msg)")
        }

        // refresh synthesized status whenever events mutate state
        refreshCurrentStatus()
    }

    // Called by external monitor when response is fully done
    public func finalizeResponse(_ finalContent: String) {
        // Replace any previous messages with the single assistant response
        messages = [
            ChatMessage(
                role: .assistant,
                content: finalContent,
                timestamp: Date()
            )
        ]
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .idle
        isGenerating = false
        refreshCurrentStatus()
    }

    private func handleError(_ error: Error) {
        // Replace messages with the error message only
        messages = [
            ChatMessage(
                role: .assistant,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            )
        ]
        liveContent = ""
        liveThinking = nil
        liveToolName = nil
        liveToolSummary = nil
        loadingState = .error(error.localizedDescription)
        isGenerating = false
        refreshCurrentStatus()
    }

    // MARK: - Helpers

    private func refreshCurrentStatus() {
        // Prefer live thinking stream
        if let thinking = liveThinking, !thinking.isEmpty {
            currentStatus = thinking
            return
        }

        // Tool activity
        if let tool = liveToolName {
            if let summary = liveToolSummary, !summary.isEmpty {
                currentStatus = "\(tool): \(summary)"
                return
            }
            currentStatus = "Running: \(tool)"
            return
        }

        // Loading error
        switch loadingState {
        case .error(let msg):
            currentStatus = "Error: \(msg)"
            return
        default:
            break
        }

        // General status text (connection, etc.)
        if !statusText.isEmpty {
            currentStatus = statusText
            return
        }

        currentStatus = nil
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
                    // Keep message view empty on mode switch; only assistant responses to user prompts should appear.
                    messages = []
                } catch {
                    handleError(error)
                }
            }
        }
    }
}
