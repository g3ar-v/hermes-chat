import Foundation

// MARK: - Local Chat Event

public enum LocalChatEvent: Sendable {
    case delta(String)
    case complete(String)
    case error(String)
}

// MARK: - UserDefaults Keys

private enum LocalChatKeys {
    static let baseURL = "localChatBaseURL"
    static let model = "localChatModel"
}

// MARK: - Local Chat Service

/// Sends messages directly to an OpenAI-compatible `/v1/chat/completions` endpoint
/// using raw HTTP streaming (SSE). No Hermes gateway, no agent, no memory.
public final class LocalChatService: @unchecked Sendable {
    public static let shared = LocalChatService()

    // MARK: - Configuration Accessors

    public static var baseURL: String {
        get { UserDefaults.standard.string(forKey: LocalChatKeys.baseURL) ?? "http://localhost:1234/v1" }
        set { UserDefaults.standard.set(newValue, forKey: LocalChatKeys.baseURL) }
    }

    public static var model: String {
        get { UserDefaults.standard.string(forKey: LocalChatKeys.model) ?? "qwen/qwen3.5-9b" }
        set { UserDefaults.standard.set(newValue, forKey: LocalChatKeys.model) }
    }

    // MARK: - State

    private var currentTask: URLSessionTask?
    private var onEvent: (@Sendable (LocalChatEvent) -> Void)?

    private init() {}

    // MARK: - Send

    /// Send a user message to the configured local endpoint and stream the response.
    /// - Parameters:
    ///   - text: The user's message text.
    ///   - onEvent: Called on the main thread for each event (delta, complete, error).
    public func send(text: String, onEvent: @escaping @Sendable (LocalChatEvent) -> Void) {
        self.onEvent = onEvent

        let rawBase = LocalChatService.baseURL
        guard let base = URL(string: rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase) else {
            onEvent(.error("Invalid base URL: \(rawBase)"))
            return
        }

        let endpoint = base.appendingPathComponent("chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": LocalChatService.model,
            "messages": [["role": "user", "content": text]],
            "stream": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            onEvent(.error("Failed to encode request: \(error.localizedDescription)"))
            return
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 300
        let session = URLSession(configuration: sessionConfig)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    Task { @MainActor in onEvent(.complete("")) }
                } else {
                    Task { @MainActor in onEvent(.error("Connection failed: \(error.localizedDescription)")) }
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                Task { @MainActor in onEvent(.error("No HTTP response")) }
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyHint = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Task { @MainActor in onEvent(.error("HTTP \(httpResponse.statusCode): \(bodyHint.prefix(200))")) }
                return
            }

            guard let data else {
                Task { @MainActor in onEvent(.error("No response data")) }
                return
            }

            // Parse SSE stream from response data
            var accumulated = ""
            guard let text = String(data: data, encoding: .utf8) else {
                Task { @MainActor in onEvent(.error("Failed to decode response")) }
                return
            }

            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data: ") else { continue }

                let payload = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty else { continue }

                if payload == "[DONE]" { break }

                guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String
                else { continue }

                accumulated += content
                Task { @MainActor in onEvent(.delta(content)) }
            }

            Task { @MainActor in onEvent(.complete(accumulated)) }
            self.currentTask = nil
        }

        self.currentTask = task
        task.resume()
    }

    // MARK: - Cancel

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        onEvent = nil
    }
}