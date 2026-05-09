import SwiftUI

// MARK: - Chat View (Root)

struct ChatView: View {
    
@StateObject private var viewModel = ChatViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        //        ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
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
            
            // Message list + safe area input
//            if !viewModel.messages.isEmpty {
                conversationContent
//            }
        }
        .environmentObject(viewModel)
        .frame(maxHeight: .infinity, alignment: .bottom)
        //        }
        //        .background(.thickMaterial)
        //        .overlay {
        //            RoundedRectangle(cornerRadius: 17, style: .continuous)
        //                .stroke(.secondary.opacity(0.5), lineWidth: 1.0)
        //        }
        //        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        //        .task {
        //            #if DEBUG
        //            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
        //                await viewModel.connect()
        //            } else {
        //                viewModel.statusText = "Preview mode"
        //            }
        //            #else
        //            await viewModel.connect()
        //            #endif
        //        }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(viewModel.messages) { message in
                        HermesMessageView(message: message)
                    }
                    
                    // Live streaming assistant bubble
                    if viewModel.loadingState.isLoading, let last = viewModel.messages.last, last.role == .user {
                        HermesMessageView(
                            message: ChatMessage(role: .assistant, content: ""),
                            isStreaming: true
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .overlay {
                if viewModel.messages.isEmpty {
                    ZStack {
                        Image(systemName: "brain.head.profile")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tertiary)
                            .frame(width: 45, height: 45)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .contentMargins(.bottom, -40, for: .scrollContent)
            .scrollIndicators(.hidden)
            //            .safeAreaInset(edge: .bottom) {
            //                InputBarView(
            //                    text: $inputText,
            //                    isLoading: viewModel.loadingState.isLoading,
            //                    chatMode: viewModel.chatMode
            //                ) { prompt in
            //                    Task { await viewModel.send(prompt) }
            //                }
            //            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // Connection status
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
//                    Text(viewModel.statusText)
//                        .font(.system(size: 11))
//                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                TextField("Ask Hermes...", text: $text, axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .lineLimit(4)
                    .frame(minHeight: 50, alignment: .center)
                    .onSubmit {
                        self.submit()
                    }
                
                Spacer()
                
                // Mode indicator
                Label(chatMode.rawValue, systemImage: chatMode.icon)
                    .foregroundStyle(.gray.opacity(0.5))
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .labelStyle(SpacedLabelStyle(spacing: 5))
            }
            .frame(height: 50)
        }
//        .padding(.top, 10)
        .padding(.horizontal)
//                .padding(.vertical, 7)
        .background(.thickMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.secondary.opacity(0.5), lineWidth: 1.0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding([.bottom, .horizontal], 15)
        .padding(.top, 5)
    }
    
    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = ""
        onSubmit(trimmed)
    }
}


// MARK: - Message View

struct HermesMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    
    var body: some View {
        ZStack(alignment: message.role == .user ? .trailing : .leading) {
            if message.role == .user {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content.isEmpty ? "…" : message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if isStreaming {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Color.accentColor.opacity(0.6))
                                    .frame(width: 5, height: 5)
                                    .opacity(0.6)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(i) * 0.15),
                                        value: isStreaming
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 36,
                    alignment: .leading
                )
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
