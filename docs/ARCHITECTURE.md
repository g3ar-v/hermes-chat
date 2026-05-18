# Building a Modern macOS Chat Client: Architecture & Implementation Patterns

## Executive Summary

The macOS chat application landscape has evolved significantly since the introduction of SwiftUI in 2019. Modern chat clients must balance performance, memory efficiency, and user experience across diverse system configurations. This document presents production-proven patterns for building floating panel chat applications that communicate with external LLM backends via JSON-RPC, with particular attention to memory management, state handling, and third-party library integration in Swift 6 concurrency environments.

---

## 1. Floating Panel Architecture on macOS

### 1.1 Window Management Strategies

macOS provides several window management APIs, each with distinct trade-offs for chat applications:

**NSWindow + NSWindowController (AppKit)**
- Most control over window behavior
- Requires bridging to SwiftUI via NSHostingView
- Necessary for level control (floating panel behavior)

**SwiftUI WindowGroup (macOS 13+)**
- Native SwiftUI approach
- Limited control over window level and ordering
- Simpler but less flexible for floating panels

**Recommended Hybrid Approach**
```swift
// Bridge AppKit window management with SwiftUI content
class ChatWindowController: NSWindowController {
    convenience init() {
        let hostingController = NSHostingController(rootView: ChatView())
        let window = NSWindow(contentViewController: hostingController)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.init(window: window)
    }
}
```

**Window Level Considerations**
- `.floating` keeps window above normal app windows but below modal panels
- `.modalPanel` risks capturing focus unintentionally
- `.statusBar` provides persistent visibility but interferes with menu bar
- Custom window levels (e.g., `.init(rawValue: 3)`) require entitlements

### 1.2 Window State Persistence

Chat applications benefit from remembering window position and size across launches:

```swift
struct WindowState: Codable {
    let frame: NSRect
    let isVisible: Bool
    let tabIndex: Int
}

class WindowStateManager {
    private let storageKey = "ChatWindowState"
    
    func saveState(_ window: NSWindow) {
        let state = WindowState(
            frame: window.frame,
            isVisible: !(window.isVisible),
            tabIndex: 0
        )
        UserDefaults.standard.setEncoded(state, forKey: storageKey)
    }
    
    func restoreState() -> WindowState? {
        return UserDefaults.standard.decoded(forKey: storageKey)
    }
}
```

**Saving Across Spaces**: macOS Spaces complicate position restoration. Use `window.collectionBehavior = [.canJoinAllSpaces]` to enable multi-space positioning, but note that user may move window per-space. Consider saving per-space state if needed.

---

## 2. JSON-RPC Communication Pattern

### 2.1 Subprocess Protocol Design

Communicating with Hermes Gateway via subprocess stdin/stdout requires careful protocol handling:

**Message Framing**
- Length-prefixed protocol recommended over newline-delimited
- Allows binary payloads and avoids partial read issues

```swift
struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: UUID
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String = "2.0"
    let id: UUID?
    let result: AnyCodable?
    let error: JSONRPCError?
}

// Send with length prefix (4 bytes little-endian)
func sendRequest(_ request: JSONRPCRequest) throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    var length = UInt32(data.count).littleEndian
    let lengthData = Data(bytes: &length, count: 4)
    
    process.stdin?.write(lengthData)
    process.stdin?.write(data)
    try process.stdin?.flush()
}
```

**Background Processing**: JSON-RPC operations must not block the main thread. Use `async/await` with `CheckedContinuation` to bridge callback-based pipe reading:

```swift
actor JSONRPCClient {
    private let process: Process
    private var continuationCache: [UUID: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    
    func request(method: String, params: [String: Any]? = nil) async throws -> JSONRPCResponse {
        let id = UUID()
        let request = JSONRPCRequest(id: id, method: method, params: params)
        
        return try await withCheckedThrowingContinuation { continuation in
            continuationCache[id] = continuation
            try? send(request)
        }
    }
}
```

### 2.2 Stateless vs Stateful Sessions

Two chat modes require different session management strategies:

**Stateless Mode**
- Fresh session per message
- No server-side context
- Lower memory footprint on backend
- Simple to implement: new connection per request or connection pooling

**Stateful (Memory) Mode**
- Persistent session with Honcho context
- Context injection from client-side
- Requires consistent connection lifecycle
- Consider reconnection logic with exponential backoff

**Session Management**
```swift
enum ChatMode {
    case stateless
    case memory(sessionId: UUID)
}

class SessionManager {
    private var activeSession: UUID?
    private let gatewayProcess: Process
    
    func startSession(mode: ChatMode) async throws {
        switch mode {
        case .stateless:
            // Stateless: no persistent session
            break
        case .memory(let sessionId):
            activeSession = sessionId
            // Inject session context into requests
        }
    }
}
```

---

## 3. Keyboard Shortcuts Integration

### 3.1 Global Hotkey Registration

Sindresorhus/KeyboardShortcuts provides a clean API for global hotkeys:

```swift
import KeyboardShortcuts

class HotkeyManager {
    static let shared = HotkeyManager()
    
    func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleChat) { [weak self] in
            self?.toggleChatWindow()
        }
        
        KeyboardShortcuts.onKeyUp(for: .newChat) { [weak self] in
            self?.startNewChat()
        }
    }
}
```

**Info.plist Configuration**
```xml
<key>NSGlobalDomain</key>
<dict>
    <key>com.apple.keyboard.modifiermapping.1452-1598-0</key>
    <dict>
        <key>annenabled</key>
        <true/>
    </dict>
</dict>
```

**Permission Flow**: macOS 14+ requires explicit user approval for global keyboard monitoring. Show an instructional alert button that opens System Settings:

```swift
Button("Open System Settings") {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
}
```

### 3.2 Hotkey Conflicts & Best Practices

**Common Conflicts**
- Spotlight hotkey (Cmd+Space)
- Alfred/Raycast launchers
- Screen recording tools (Cmd+Shift+5)
- System accessibility features (VoiceOver)

**Resolution Strategies**
- Prefer modifier-heavy combos: `⌘⇧⌥A` rather than `⌘A`
- Allow user customization in preferences
- Detect conflicts via `CGEventTap` (advanced)
- Graceful fallback: show window via dock icon or menu bar

**Performance Considerations**
Global hotkeys wake the app, but should defer heavy work:
```swift
KeyboardShortcuts.onKeyUp(for: .toggleChat) { [weak self] in
    DispatchQueue.main.async { [weak self] in
        self?.toggleChatWindow()
    }
}
```

---

## 4. Markdown Rendering with Third-Party Libraries

### 4.1 Library Selection Criteria

When evaluating Markdown renderers for macOS/SwiftUI:

**Rendering Engine**
- GitHub-flavored Markdown (GFM) support?
- Tables, task lists, code blocks?
- Syntax highlighting integration?

**Performance Metrics**
- Rendering speed for large documents (5000+ lines)
- Memory footprint per rendered view
- Incremental update support (critical for streaming)
- Caching behavior

**API Compatibility**
- SwiftUI View vs UIViewRepresentable
- Text attachment handling
- Link interception (custom URL schemes)
- Theming/customization hooks

### 4.2 LiYanan2004/MarkdownView: Known Patterns

Based on commit `31e52d2` (pinned to avoid concurrency issue):

**Initialization**
```swift
// IMPORTANT: No colon in initializer for this revision
MarkdownView(text: markdownString)
// NOT MarkdownView(text: "..." with label: ...)
```

**Modifiers Available**
- `.markdownRenderingThread()` removes concurrency issue in newer versions but not available in pinned revision
- `.disableLineNumber()` for cleaner output
- `.theme(.default)` for styling

**Streaming Updates**
The library supports incremental updates efficiently:
```swift
@State private var markdownText = ""

var body: some View {
    MarkdownView(text: markdownText)
        .onChange(of: messageContent) { newValue in
            // Efficient: only re-renders changed portion
            markdownText.append(newValue)
        }
}
```

**Memory Considerations**
Large Markdown documents can consume significant memory. Strategies:
- Pagination for history (load 100 messages at a time)
- Trim trailing whitespace and normalize newlines
- Consider plain-text fallback for extremely long messages (>10KB)
- Monitor memory with Instruments; the library has known leaks in some edge cases

### 4.3 Concurrency Issue & Pinning Strategy

The upstream library introduced an actor concurrency issue with `static var shared` in Swift 6. Pinning to `31e52d2` is correct, but consider:

**Tracking Upstream**
```bash
# Check if issue resolved
git -C ~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/MarkdownView log --oneline --since="2025-01-01" | grep -i "actor\|shared\|static"
```

**Future Migration Path**
1. Monitor upstream PRs for `static var` fixes
2. Test with Xcode 16 betas for compiler workarounds
3. Consider forking if upstream stalls
4. Alternative: Precompile to NSAttributedString for full control

---

## 5. Memory Management & Performance Optimization

### 5.1 Memory Profiling Checklist

**Instruments Templates**
- Allocations (track persistent growth)
- Leaks (esp. MarkdownView instances)
- VM Tracker (detect virtual memory pressure)
- Energy Log (waking CPU via global shortcuts)

**Common Leak Sources**
1. **Text Views**: Each MarkdownView retains attributed strings
   - Solution: Reuse view instances; limit history view count
2. **Images/Syntax Highlighting**: Colored text attributes accumulate
   - Solution: Use shared `NSTextStorage` where appropriate
3. **Delegate Retain Cycles**: `NSTextView` delegates not weak
   - Solution: Wrap in `Weak` property wrapper
4. **Timers**: `CADisplayLink` not invalidated
   - Solution: Store in `@StateObject` with `.onDisappear` cleanup

### 5.2 Memory Budget per Feature

| Feature | Target Memory | Notes |
|---------|---------------|-------|
| Visible chat view | < 5 MB | 1-2 messages rendered |
| Message history (100) | < 20 MB | Lazy-loaded cells |
| Markdown renderer pool | < 10 MB | Reuse instances |
| JSON-RPC buffer | < 1 MB | Circular buffer |
| Keyboard shortcut state | < 100 KB | Minimal |

**Memory Warning Handling**
```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.purgeCaches()
}

private func purgeCaches() {
    // Clear any cached syntax highlighting
    // Remove offscreen message views
    // Trim history if needed
}
```

### 5.3 Performance Optimization Techniques

**View Identity**: Use `id()` generously to help SwiftUI diffing:
```swift
ForEach(messages) { message in
    MessageView(message: message)
        .id(message.id)  // Critical for reuse
}
```

**Lazy Loading**: Only render visible + small buffer:
```swift
LazyVStack {
    ForEach(visibleMessages) { message in
        MessageRow(message: message)
    }
}
```

**Debounce Updates**: Streaming responses shouldn't re-render every character:
```swift
.onChange(of: streamedText) { newValue in
    Task {
        try await Task.sleep(for: .milliseconds(50))  // Debounce
        await MainActor.run {
            debouncedText = newValue
        }
    }
}
```

---

## 6. Error Handling & Observability

### 6.1 Structured Error Types

Define domain-specific errors:

```swift
enum ChatError: LocalizedError {
    case connectionFailed(Error)
    case invalidResponse(Data)
    case sessionExpired
    case renderingFailed(String)
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Connection to gateway lost"
        case .invalidResponse: "Invalid response from backend"
        case .sessionExpired: "Session expired. Please start a new chat."
        case .renderingFailed: "Failed to render message"
        case .permissionDenied: "Keyboard shortcut permission denied"
        }
    }
}
```

### 6.2 Recovery Strategies

**Connection Drops**: Exponential backoff reconnection:
```swift
func connectWithRetry(attempt: Int = 0) async throws {
    do {
        try await connect()
    } catch {
        if attempt < 5 {
            let delay = pow(2.0, Double(attempt))
            try await Task.sleep(for: .seconds(delay))
            try await connectWithRetry(attempt: attempt + 1)
        } else {
            throw error
        }
    }
}
```

**Streaming Interruption**: Partial message recovery:
```swift
// Store partial state, offer to continue or restart
if streamInterrupted {
    showAlert(title: "Stream Interrupted", 
              message: "Would you like to continue the previous response?") { _ in
        resumeSession(from: lastCompleteMessage)
    }
}
```

### 6.3 Logging & Telemetry

**Structured Logging** (considers privacy):
```swift
struct LogEvent {
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
    let metadata: [String: String]
}

enum LogLevel {
    case debug, info, warning, error
}

// Log to file (rotated daily)
class FileLogger {
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.hermeschat.logging")
    
    func log(_ event: LogEvent) {
        queue.async {
            // JSON format for easy parsing
            let json = try? JSONEncoder().encode(event)
            // Append to daily log file...
        }
    }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Test Coverage

**JSON-RPC Layer**
- Message encoding/decoding roundtrip
- Error handling for malformed responses
- Cancellation token handling

**Window State**
- Save/restore across app launches
- Multi-space position handling
- Minimized vs visible state

**Markdown Parsing**
- GFM edge cases (tables, code blocks)
- Unicode handling (emoji, RTL text)
- Extremely long lines (prevent crashes)

### 7.2 Integration Tests

- End-to-end gateway communication
- Hotkey registration & permission flow
- Streaming display updates
- Memory growth over sustained usage

### 7.3 UI Tests (XCTest)

```swift
func testToggleChatWindow() async throws {
    let app = XCUIApplication()
    app.launch()
    
    // Window initially hidden
    XCTAssertFalse(app.windows["ChatWindow"].exists)
    
    // Simulate hotkey press
    XCUIDevice.shared.press(.keyboardShortcut("T", modifiers: [.command, .shift]))
    
    // Window appears
    XCTAssertTrue(app.windows["ChatWindow"].waitForExistence(timeout: 2))
}
```

---

## 8. XcodeGen Project Configuration

### 8.1 Project.yml Structure

```yaml
name: HermesChat
targets:
  HermesChat:
    type: application
    platform: macOS
    deploymentTarget: '14.0'
    sources: [HermesChat]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.hermeschat.app
      CODE_SIGN_ENTITLEMENTS: HermesChat/Entitlements.plist
      DEVELOPMENT_TEAM: YOUR_TEAM_ID
      OTHER_SWIFT_FLAGS: [$(inherited), -package-name $(PRODUCT_BUNDLE_IDENTIFIER)]
    dependencies:
      - package: KeyboardShortcuts
        product: KeyboardShortcuts
      - package: MarkdownView
        product: MarkdownView
        requirement: exact(31e52d2)
    buildPhases:
      - targetDependencies: []
      - sources:
          name: Compile Sources
      - frameworks:
          name: Embed Frameworks
      - copyFiles:
          name: Copy Resources
          destination: resources
          files: [Resources/**/*]
```

### 8.2 Entitlements Configuration

**Requesting Accessibility Permission**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.keyboard</key>
    <true/>  <!-- Required for global hotkeys -->
    <key>com.apple.security.personal-information.location</key>
    <false/>
</dict>
</plist>
```

**Note**: Global hotkeys do NOT require Accessibility permission; they require `com.apple.security.device.keyboard` entitlement AND user approval via System Settings privacy panel.

---

## 9. Deployment & Distribution

### 9.1 Code Signing & Notarization

**Signing Script**:
```bash
#!/bin/zsh
#!/usr/bin/env zsh

XCODE_PROJECT="HermesChat.xcodeproj"
SCHEME="HermesChat"
TEAM_ID="YOUR_TEAM_ID"
BUNDLE_ID="com.hermeschat.app"

# Build
xcodebuild -project "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "./build/$SCHEME.xcarchive" \
  archive

# Export
xcodebuild -exportArchive \
  -archivePath "./build/$SCHEME.xcarchive" \
  -exportOptionsPlist "ExportOptions.plist" \
  -exportPath "./build"

# Notarize
xcrun notarytool submit "./build/${SCHEME}.app" \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple "./build/${SCHEME}.app"
```

### 9.2 Sparkle Updates

Consider Sparkle framework for automatic updates:

```yaml
# Project.yml dependencies
dependencies:
  - package: Sparkle
    product: Sparkle
    requirement: from: "2.5.0"
```

**Update Configuration**:
- Feed URL: HTTPS endpoint with appcast.xml
- Delta updates enabled (bandwidth savings)
- Ed signature verification

---

## 10. Future Considerations

### 10.1 Migration to Swift 6 Concurrency

When MarkdownView resolves actor concurrency:

**Current pattern** (workaround):
```swift
// Pinned version requires explicit threading
MarkdownView(text: message)
    .markdownRenderingThread()  // Available in newer versions only
```

**Future Swift 6 native**:
```swift
@MainActor
struct MessageView: View {
    @ObservableObject var viewModel: MessageViewModel
    
    var body: some View {
        MarkdownView(text: viewModel.renderedMarkdown)
            .task(id: viewModel.content) {
                // Actor-safe rendering
            }
    }
}
```

### 10.2 Multi-Platform Expansion

iPadOS/macOS Catalyst considerations:
- Touch-optimized UI (larger buttons)
- Multi-window support via UIScene
- Keyboard shortcuts via UIKeyCommand

### 10.3 AI Agent Integration

HermesAgent subagent orchestration for:
- Automated issue triage
- PR review (integrate with GitHub)
- Code quality analysis
- Documentation generation

---

## Appendix A: Git Flow & Conventions

### Branch Strategy
```
main (production)
develop (integration)
feature/<ticket>-description (feature work)
bugfix/<ticket>-description (hotfixes)
release/<version> (release prep)
```

### Commit Message Format
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type**: feat, fix, refactor, docs, test, chore, revert, build, ci
**Scope**: component or area (optional)
**Breaking Change**: Add `BREAKING CHANGE:` in footer or `!` after type

**Examples**:
- `feat(chat): add streaming message display`
- `fix(json-rpc): handle connection timeout properly`
- `refactor(window): extract WindowStateManager for reuse`

---

## Appendix B: Resource Links

**Apple Documentation**
- [Window Management](https://developer.apple.com/documentation/appkit/nswindow)
- [SwiftUI on macOS](https://developer.apple.com/tutorials/swiftui)
- [App Sandbox Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)

**Dependency Documentation**
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [MarkdownView](https://github.com/LiYanan2004/MarkdownView)
- [Hermes Gateway Protocol](https://github.com/nousresearch/hermes-gateway)

**Performance Tools**
- [Instruments User Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/InstrumentsUserGuide/)
- [Memory Debugging in Xcode](https://developer.apple.com/videos/play/wwdc2023/10071/)

---

*Document Version: 1.2*  
*Last Updated: 2026-05-13*  
*Target: HermesChat v1.0 Release Candidate*