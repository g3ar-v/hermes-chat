import SwiftUI
import MarkdownView

// MARK: - Chat View (Root)

struct ChatView: View {
    
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Top toolbar
            // toolbar
            
            // Divider()
            InputBarView(
                text: $inputText,
                isLoading: viewModel.loadingState.isLoading,
                chatMode: viewModel.chatMode
            ) { prompt in
                Task { await viewModel.send(prompt) }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 15)
            
            // Message list appears when there are messages or streaming content
            if !viewModel.messages.isEmpty || !viewModel.liveContent.isEmpty {
                conversationContent
                    .frame(maxWidth: 720)
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
    
    // MARK: - Conversation Content
    
    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Last assistant response or streaming content
            if let last = viewModel.messages.last(where: { $0.role == .assistant }) {
                MarkdownView(last.content)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: 720, alignment: .leading)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
//            } else if !viewModel.liveContent.isEmpty {
//                // Show streaming assistant text while response is in progress
//                MarkdownView(viewModel.liveContent)
//                    .textSelection(.enabled)
//                    .padding()
//                    .frame(maxWidth: 720, alignment: .leading)
//                    .background(.thickMaterial)
//                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
//            }
            
            
            
            // Loading dots
            //            if viewModel.loadingState.isLoading {
            //                HStack(spacing: 4) {
            //                    ForEach(0..<3, id: \.self) { i in
            //                        Circle()
            //                            .fill(Color.accentColor)
            //                            .frame(width: 6, height: 6)
            //                            .animation(
            //                                .easeInOut(duration: 0.6)
            //                                .repeatForever()
            //                                .delay(Double(i) * 0.15),
            //                                value: viewModel.loadingState.isLoading
            //                            )
            //                    }
            //                }
            //                .padding(.horizontal)
            //                .frame(maxWidth: 720, alignment: .leading)
            //            }
        }
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
    }
}

// MARK: - Input Bar

struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    let chatMode: ChatMode
    let onSubmit: (String) -> Void
    
    @EnvironmentObject private var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 2) {
                
                TextField("Ask Hermes...", text: $text, axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .lineLimit(4)
                    .frame(minHeight: 50, alignment: .center)
                    .onSubmit {
                        self.submit()
                    }
                
            }
            .padding(2)
            //            .frame(height: 50)
            
            
            
            HStack(alignment: .firstTextBaseline) {
                
                Group {
                    
                    // Mode toggle — Stateless / Memory
                    //                    HStack(spacing: 4) {
                    //                        ForEach(ChatMode.allCases) { mode in
                    //                            Button {
                    //                                viewModel.chatMode = mode
                    //                            } label: {
                    //                                HStack(spacing: 4) {
                    //                                    Image(systemName: mode.icon)
                    //                                        .font(.system(size: 10, weight: .semibold))
                    //                                    Text(mode.rawValue)
                    //                                        .font(.system(size: 11, weight: .medium))
                    //                                }
                    //                                .padding(.horizontal, 8)
                    //                                .padding(.vertical, 4)
                    //                                .background(
                    //                                    viewModel.chatMode == mode
                    //                                    ? Color.accentColor.opacity(0.2)
                    //                                    : Color.clear
                    //                                )
                    //                                .foregroundColor(
                    //                                    viewModel.chatMode == mode ? .accentColor : .secondary
                    //                                )
                    //                                .clipShape(Capsule())
                    //                            }
                    //                            .buttonStyle(.plain)
                    //                        }
                    //                    }
                    
                    // Mode indicator
                    Label(chatMode.rawValue, systemImage: chatMode.icon)
                        .foregroundStyle(.gray.opacity(0.5))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .labelStyle(SpacedLabelStyle(spacing: 5))
                    
                    
                    
                }
                
                
                
                Spacer()
                
                // Connection status
//                HStack(spacing: 5) {
//                    Circle()
//                        .fill(viewModel.isConnected ? Color.green : Color.orange)
//                        .frame(width: 7, height: 7)
//                }
                // Status indicators
                if let status = viewModel.currentStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                
            }
            
            
            
        }.padding(.top, 3)
        .padding(.bottom, 7)
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

