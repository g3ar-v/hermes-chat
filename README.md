# HermesChat

macOS floating-panel chat client for [Hermes](https://github.com/nousresearch/hermes-agent) — a native SwiftUI interface that connects to the Hermes Gateway via JSON-RPC over a subprocess.

## Features

- **Floating panel** — stays above other windows, follows across Spaces, hides on defocus
- **Global hotkey** — ⌘⌥L toggles the panel from anywhere
- **Menu bar icon** — left-click toggle, right-click context menu (show, settings, quit)
- **Streaming Markdown** — live-rendered GFM responses via MarkdownView
- **Live status** — thinking, tool execution, and connection state in real-time
- **Interrupt** — stop generation mid-stream
- **Dual mode** — stateless and memory (Honcho) chat modes
- **Swift 6** — strict concurrency with minimal Swift 6 warnings

## Requirements

- macOS 14.0+
- Xcode 16.0+
- Swift 6.0
- [Hermes Agent](https://github.com/nousresearch/hermes-agent) installed (provides the `tui_gateway.entry` subprocess)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & Run

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open HermesChat.xcodeproj
```

Or build from the command line:

```bash
xcodegen generate && xcodebuild -project HermesChat.xcodeproj -scheme HermesChat -configuration Debug build
```

## Project Structure

```
HermesChat/
├── Sources/
│   ├── App/
│   │   ├── AppDelegate.swift              # NSApplication lifecycle, floating panel, status bar
│   │   ├── KeyboardShortcuts+Definitions.swift  # Global hotkey (⌘⌥L default)
│   │   └── main.swift                     # Entry point
│   ├── Models/
│   │   ├── ChatMessage.swift              # Message model, loading state
│   │   └── GatewayModels.swift            # Gateway event types and session models
│   ├── Services/
│   │   ├── GatewayClient.swift            # JSON-RPC subprocess client (stdin/stdout)
│   │   └── HonchoMemoryService.swift      # Honcho memory integration
│   ├── ViewModels/
│   │   └── ChatViewModel.swift            # Main chat state management
│   └── Views/
│       ├── ChatView.swift                 # Main chat UI
│       └── ComponentStyles.swift          # Shared button/menu styles
├── Resources/
│   └── Assets.xcassets/
├── Info.plist
├── HermesChat.entitlements
└── project.yml                            # XcodeGen project spec
```

## How It Works

1. **Launch** → creates a borderless `NSPanel` with SwiftUI content, registers the global hotkey, and sets up the menu bar item.
2. **Toggle** → hotkey or menu bar click shows/hides the floating panel.
3. **Send** → `GatewayClient` spawns a Python subprocess (`tui_gateway.entry`), communicates via newline-delimited JSON-RPC over stdin/stdout.
4. **Stream** → the gateway emits events (`messageDelta`, `thinkingDelta`, `toolStart`) → `ChatViewModel` updates published state → SwiftUI renders Markdown live.
5. **Hide** → panel dismisses on key window resignation, returns via hotkey.

## Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration |
| [MarkdownView](https://github.com/LiYanan2004/MarkdownView) | GFM rendering (pinned to `31e52d2` for Swift 6 compat) |

## Configuration

| Setting | Default | How to Change |
|---------|---------|---------------|
| Hotkey | ⌘⌥L | Edit `KeyboardShortcuts+Definitions.swift` |
| Window size | 480×480 | Edit `createPanel()` in `AppDelegate.swift` |
| Gateway timeout | 120s | `GatewayClient.request()` timeout |

The gateway respects `HERMES_HOME` and `HERMES_PROFILE` environment variables. If `HERMES_HOME` is unset but a profile is active, it auto-derives the path.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for an in-depth architecture and implementation patterns document covering window management, JSON-RPC protocol design, memory management, testing strategy, and deployment.
