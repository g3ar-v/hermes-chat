import Foundation

// MARK: - JSON-RPC Errors

public enum GatewayClientError: Error, LocalizedError, Sendable {
    case notRunning
    case timeout(String)
    case protocolError(String)
    case rpcError(String)
    case sessionNotCreated

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Gateway process is not running"
        case .timeout(let method): return "Gateway method '\(method)' timed out"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .rpcError(let msg): return "RPC error: \(msg)"
        case .sessionNotCreated: return "Failed to create session"
        }
    }
}

/// Thread-safe wrapper so a CheckedContinuation can be safely resumed from a
/// @Sendable closure. [String:Any] is not Sendable, so we serialize to Data
/// (which IS Sendable) before storing and deserialize on resume.
private final class ContinuationHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Data, Error>?

    init(_ c: CheckedContinuation<Data, Error>) {
        self._continuation = c
    }

    func resume(returning dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            resume(throwing: GatewayClientError.protocolError("failed to serialize dict"))
            return
        }
        resume(data: data)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        _continuation?.resume(throwing: error)
        _continuation = nil
    }

    private func resume(data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _continuation?.resume(returning: data)
        _continuation = nil
    }
}

// MARK: - Gateway Client

/// Communicates with the Hermes Gateway over JSON-RPC via a subprocess.
/// All mutable state is protected by a serial DispatchQueue.
public final class GatewayClient: @unchecked Sendable {
    private var proc: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var pending: [Int: (Result<Any, Error>) -> Void] = [:]
    private var eventHandlers: [(GatewayEvent) -> Void] = []
    private var requestId: Int = 0
    private var isReady = false

    private let queue = DispatchQueue(label: "com.hermes.gateway-client")

    public static let shared = GatewayClient()

    private init() {}

    // MARK: - Lifecycle

    public func start() async throws {
        guard proc == nil else { return }

        let python = try findPython()
        proc = Process()
        proc?.executableURL = URL(fileURLWithPath: python)
        proc?.arguments = ["-m", "tui_gateway.entry"]
        // Propagate current environment but ensure subprocesses inherit a profile-aware HERMES_HOME.
        var env = ProcessInfo.processInfo.environment
        if (env["HERMES_HOME"] ?? "").isEmpty, let profile = env["HERMES_PROFILE"], !profile.isEmpty {
            // If HERMES_HOME is unset but a profile is active, point subprocesses at the profile dir.
            let home = NSHomeDirectory()
            env["HERMES_HOME"] = "\(home)/.hermes/profiles/\(profile)"
        }
        proc?.environment = env

        stdin = Pipe()
        stdout = Pipe()
        proc?.standardInput = stdin
        proc?.standardOutput = stdout

        let outputHandle = stdout!.fileHandleForReading
        let client = self

        outputHandle.readabilityHandler = { _ in
            let data = outputHandle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                // Debug prints removed
                if let rawText = String(data: data, encoding: .utf8) {
                    _ = rawText // intentionally unused; preserve path for future logging hook
                } else {
                    _ = data.count
                }
                client.handleStdout(data)
            }
        }

        proc?.terminationHandler = { _ in
            Task { @MainActor in
                client.handleTermination()
            }
        }

        try proc?.run()
        if let pid = proc?.processIdentifier {
            _ = pid // process started; debug print removed
        }

        // Wait for gateway.ready
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class HandlerState: @unchecked Sendable {
                var isActive = true
            }
            let state = HandlerState()

            let handler: @Sendable (GatewayEvent) -> Void = { _ in
                guard state.isActive else { return }
                state.isActive = false
                continuation.resume()
            }

            client.addEventHandler(handler)

            Task {
                try? await Task.sleep(for: .seconds(15))
                guard state.isActive else { return }
                state.isActive = false
                continuation.resume(throwing: GatewayClientError.timeout("gateway ready"))
            }
        }

        isReady = true
    }

    public func stop() {
        queue.sync {
            pending.values.forEach { $0(.failure(GatewayClientError.notRunning)) }
            pending.removeAll()
        }
        proc?.terminate()
        proc = nil
        stdin = nil
        stdout = nil
        isReady = false
    }

    private func handleTermination() {
        print("[TUI-GW] terminated")
        queue.sync {
            pending.values.forEach { $0(.failure(GatewayClientError.notRunning)) }
            pending.removeAll()
        }
        proc = nil
        stdin = nil
        stdout = nil
        isReady = false
    }

    // MARK: - RPC

    public func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let stdin = stdin, let proc = proc, proc.isRunning else {
            throw GatewayClientError.notRunning
        }

        let id = queue.sync { requestId }
        queue.async { self.requestId += 1 }

        let req: [String: Any] = [
            "id": id,
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]

        let reqData = try JSONSerialization.data(withJSONObject: req)
        guard let line = String(data: reqData, encoding: .utf8) else {
            throw GatewayClientError.protocolError("failed to encode request")
        }

        // Debug prints removed for outgoing requests
        _ = line // keep for potential future structured logging

        stdin.fileHandleForWriting.write(line.appending("\n").data(using: .utf8)!)

        let data = try await withCheckedThrowingContinuation { (rawContinuation: CheckedContinuation<Data, Error>) in
            let capturedId = id
            let holder = ContinuationHolder(rawContinuation)

            queue.async {
                self.pending[capturedId] = { result in
                    switch result {
                    case .success(let v):
                        guard let dict = v as? [String: Any] else {
                            holder.resume(throwing: GatewayClientError.protocolError("expected dict"))
                            return
                        }
                        holder.resume(returning: dict)
                    case .failure(let e):
                        holder.resume(throwing: e)
                    }
                }
            }

            // Timeout
            let client = self
            Task {
                try? await Task.sleep(for: .seconds(120))
                client.queue.async {
                    if let p = client.pending.removeValue(forKey: capturedId) {
                        p(.failure(GatewayClientError.timeout(method)))
                    }
                }
            }
        }

        // Deserialize Data back to [String: Any]
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayClientError.protocolError("invalid response format")
        }
        return result
    }

    private func handleStdout(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) else { return }

        // Debug prints removed for decoded lines
        _ = line

        guard let json = try? JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as? [String: Any] else {
            return
        }

        // RPC response
        if let id = json["id"] as? Int {
            let handler = queue.sync { self.pending.removeValue(forKey: id) }
            if let cb = handler {
                if let error = json["error"] as? [String: Any] {
                    cb(.failure(GatewayClientError.rpcError(error["message"] as? String ?? "unknown")))
                } else {
                    cb(.success(json["result"] as Any))
                }
            }
            return
        }

        // Event
        if json["method"] as? String == "event",
           let params = json["params"] as? [String: Any],
           let type = params["type"] as? String {
            let payload = params["payload"] as? [String: Any]
            if let event = GatewayEvent.from(type: type, payload: payload) {
                let handlers: [(GatewayEvent) -> Void] = queue.sync { eventHandlers }
                for handler in handlers {
                    handler(event)
                }
            }
        }
    }

    // MARK: - Session Management

    public struct SessionCreateResult: Sendable {
        public let sessionId: String
        public let info: GatewaySessionInfo?
    }

    public func createSession() async throws -> SessionCreateResult {
        let result = try await request("session.create")
        guard let sessionId = result["session_id"] as? String else {
            throw GatewayClientError.sessionNotCreated
        }
        var info: GatewaySessionInfo?
        if let i = result["info"] as? [String: Any] {
            info = GatewaySessionInfo(
                sessionId: i["session_id"] as? String ?? sessionId,
                startedAt: i["started_at"] as? Int ?? 0,
                messageCount: i["message_count"] as? Int ?? 0,
                model: i["model"] as? String,
                provider: i["provider"] as? String,
                title: i["title"] as? String ?? ""
            )
        }
        return SessionCreateResult(sessionId: sessionId, info: info)
    }

    public func submitPrompt(sessionId: String, text: String) async throws {
        let _ = try await request("prompt.submit", params: [
            "session_id": sessionId,
            "text": text
        ])
    }

    public func interrupt(sessionId: String) async throws {
        let _ = try await request("session.interrupt", params: [
            "session_id": sessionId
        ])
    }

    // MARK: - Events

    public func addEventHandler(_ handler: @escaping @Sendable (GatewayEvent) -> Void) {
        queue.async {
            self.eventHandlers.append(handler)
        }
    }

    public var ready: Bool { isReady }

    // MARK: - Python Discovery

    private func findPython() throws -> String {
        let candidates = [
            "/Users/vonneumann/.hermes/hermes-agent/venv/bin/python",
            "/Users/vonneumann/.hermes/hermes-agent/venv/bin/python3",
            "python3",
            "python"
        ]
        for candidate in candidates {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: candidate)
            p.arguments = ["--version"]
            let o = Pipe()
            p.standardOutput = o
            p.standardError = o
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 { return candidate }
            } catch {}
        }
        throw GatewayClientError.notRunning
    }
}
