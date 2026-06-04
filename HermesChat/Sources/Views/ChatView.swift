import MarkdownView
import SwiftUI

// MARK: - Chat View (Root)

struct ChatView: View {

    @StateObject private var viewModel = ChatViewModel()
    @State private var conversationSize: CGSize = CGSize(width: 0, height: 100)
    @FocusState private var isInputFocused: Bool
    @State private var cardIndex: Int = 0 {
        didSet {
            viewModel.chatMode = cardIndex == 0 ? .stateless : .memory
        }
    }
    @State private var localInputText: String = ""
    @State private var memoryInputText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top toolbar
            // toolbar

            // Divider()
            // CardStack wrapping stateless and memory input bars
            CardStack(
                [
                    AnyView(
                        InputBarView(
                            text: $localInputText,
                            loadingState: viewModel.loadingState,
                            chatMode: .stateless,
                            showProfile: false
                        ) { prompt in
                            Task { await viewModel.send(prompt) }
                        }),
                    AnyView(
                        InputBarView(
                            text: $memoryInputText,
                            loadingState: viewModel.loadingState,
                            chatMode: .memory,
                            showProfile: true
                        ) { prompt in
                            Task { await viewModel.send(prompt) }
                        }),
                ], selectedIndex: $cardIndex
            )
            .frame(maxWidth: 720)

            // Message list appears when there are messages or streaming content
            if !viewModel.messages.isEmpty || !viewModel.liveContent.isEmpty {
                conversationContent
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 15)
            }
        }
        .environmentObject(viewModel)

        .task {
            #if DEBUG
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                    await viewModel.connect()
                } else {
                    viewModel.statusText = "Preview mode"
                }
            #else
                await viewModel.connect()
            #endif
        }
        .environmentObject(viewModel)

        .onReceive(NotificationCenter.default.publisher(for: .hermesToggleChatMode)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                cardIndex = cardIndex == 0 ? 1 : 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hermesNewChat)) { _ in
            viewModel.resetConversation()
        }
    }

    // MARK: - Conversation Content

    private var conversationContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Last assistant response or streaming content
                    if let last = viewModel.messages.last(where: { $0.role == .assistant }) {
                        MarkdownView(last.content)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(88)
                    } else if !viewModel.liveContent.isEmpty {
                        MarkdownView(viewModel.liveContent)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(88)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newValue in
                    conversationSize.width = newValue.width
                    conversationSize.height = min(max(newValue.height, 20), 500)
                }
            }  // Scroll to bottom
            //            .onChange(of: viewModel.messages.last?.content) {
            //                DispatchQueue.main.async {
            //                    withAnimation {
            //                        proxy.scrollTo(88, anchor: .bottom)
            //                    }
            //                }
            //            }
            //            .onChange(of: viewModel.liveContent) {
            //                DispatchQueue.main.async {
            //                    withAnimation {
            //                        proxy.scrollTo(88, anchor: .bottom)
            //                    }
            //                }
            //            }
        }
        .frame(height: conversationSize.height)
        .contentMargins(.horizontal, 10, for: .scrollContent)
        //        .scrollIndicators(.hidden)
        .background(.ultraThickMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.secondary.opacity(0.5), lineWidth: 1.0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Sidebar toggle placeholder (no sidebar, but preserves the icon)
            Button {
                // No-op: no sidebar in HermesChat
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(HighlightButtonStyle())
            .help("Sidebar")

            Spacer()

            // Mode toggle — Stateless / Memory
            HStack(spacing: 4) {
                ForEach(ChatMode.allCases) { mode in
                    Button {
                        viewModel.chatMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            viewModel.chatMode == mode
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                        .foregroundColor(
                            viewModel.chatMode == mode ? .accentColor : .secondary
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Connection status
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(viewModel.statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Stop button
            if viewModel.loadingState.isLoading {
                Button {
                    Task { await viewModel.stopGenerating() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .fontDesign(.rounded)
        .fontWeight(.semibold)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
    }

}

// MARK: - Input Bar

struct InputBarView: View {
    @Binding var text: String
    let loadingState: LoadingState
    let chatMode: ChatMode
    let showProfile: Bool
    let onSubmit: (String) -> Void

    private var isLoading: Bool { loadingState.isLoading }

    @AppStorage("isPinned") private var isPinned = false
    @EnvironmentObject private var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                Button {
                    isPinned.toggle()
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.caption2)
                        .foregroundColor(isPinned ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin panel" : "Pin panel")
                .padding(.top, 2)
            }
            HStack(alignment: .center, spacing: 2) {

                TextField("Ask Hermes...", text: $text, axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .lineLimit(4)
                    .frame(minHeight: 34, alignment: .center)
                    .onSubmit {
                        self.submit()
                        isFocused = false
                        //                        let temp_text = text
                        //                        text = ""
                        //                        text = temp_text

                    }

            }
            // .padding(2)
            //            .frame(height: 50)

            HStack(alignment: .firstTextBaseline, spacing: 8) {

                Group {

                    // Settings menu button (first item in toolbar)
                    Menu {
                        Section("Mode") {
                            Button {
                                viewModel.chatMode = .stateless
                            } label: {
                                Label("Stateless", systemImage: ChatMode.stateless.icon)
                            }
                            Button {
                                viewModel.chatMode = .memory
                            } label: {
                                Label("Memory", systemImage: ChatMode.memory.icon)
                            }
                        }
                        Divider()
                        Button {
                            // TODO: open settings
                        } label: {
                            Label("Settings...", systemImage: "gearshape")
                        }
                        Divider()
                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Label("Quit", systemImage: "power")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.highlightOnHover)

                    // Mode status label (shown separately)
                    Label(chatMode.rawValue, systemImage: chatMode.icon)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary.opacity(0.6))

                    // Model label
                    if let model = viewModel.modelLabel {
                        Text(model)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }

                    if showProfile, let profile = viewModel.chatProfile {
                        Text(profile)
                            .font(.caption2)
                    }

                }

                Spacer()

                // Connection status
                //                HStack(spacing: 5) {
                //                    Circle()
                //                        .fill(viewModel.isConnected ? Color.green : Color.orange)
                //                        .frame(width: 7, height: 7)
                //                }
                // Animated status indicators
                if case .error(let msg) = loadingState {
                    ErrorIndicator(message: msg) {
                        viewModel.dismissError()
                    }
                } else if isLoading {
                    ProcessingIndicator()
                } else if let status = viewModel.currentStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }

            }.frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 3)
        //        .padding(.bottom, 7)
        .padding(.horizontal)
        //                .padding(.vertical, 7)
        .background(.thickMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.secondary.opacity(0.5), lineWidth: 1.0)

        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        //        .padding([.bottom, .horizontal], 15)
        //        .padding(.top, 5)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        // Deselect text without clearing — move cursor to end
        text = text
    }
}
