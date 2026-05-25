import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("localChatBaseURL") private var baseURL = "http://localhost:1234/v1"
    @AppStorage("localChatModel") private var model = "qwen/qwen3.5-9b"

    var body: some View {
        TabView {
            Form {
                Section("Local Endpoint") {
                    TextField("Base URL", text: $baseURL)
                        .font(.body)
                        .textFieldStyle(.roundedBorder)
                        .help("The base URL of your OpenAI-compatible API (e.g. http://localhost:1234/v1)")

                    TextField("Model", text: $model)
                        .font(.body)
                        .textFieldStyle(.roundedBorder)
                        .help("The model name served by the endpoint (e.g. qwen/qwen3.5-9b)")
                }

                Section {
                    Button("Test Connection") {
                        testConnection()
                    }
                }
            }
            .tabItem { Label("Local Chat", systemImage: "brain") }
            .padding()
        }
        .frame(width: 400, height: 280)
    }

    private func testConnection() {
        guard let base = URL(string: baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL) else { return }
        let endpoint = base.appendingPathComponent("models")

        URLSession.shared.dataTask(with: endpoint) { data, response, error in
            Task { @MainActor in
                if let error = error {
                    presentAlert(message: "Connection failed: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    presentAlert(message: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
                if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let names = models.compactMap { $0["id"] as? String }
                    presentAlert(message: "Connected. Available models: \(names.joined(separator: ", "))")
                } else {
                    presentAlert(message: "Connected (port \(base.port ?? 80))")
                }
            }
        }.resume()
    }

    private func presentAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "HermesChat Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setFrameAutosaveName("hermesChatSettings")
        self.init(window: window)
    }
}