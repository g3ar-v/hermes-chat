@preconcurrency import AppKit
import SwiftUI

// MARK: - Floating Panel
@MainActor
final class FloatingPanel: NSPanel, NSWindowDelegate {
    var isFileImporterVisible: Bool = false

    private let padding: CGFloat = 10

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer deferred: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable], backing: backing,
            defer: deferred)
        self.delegate = self

        self.setFrameAutosaveName("hermesChat")
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior.insert(.fullScreenAuxiliary)
        self.collectionBehavior.insert(.canJoinAllSpaces)

        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        if !isFileImporterVisible {
            orderOut(nil)
        }
    }

    func updateFileImporterVisibility(_ isVisible: Bool) {
        isFileImporterVisible = isVisible
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        createPanel()
        createStatusBarItem()
        registerGlobalHotkey()
    }

    private func createPanel() {
        let chatView = ChatView()
            .frame(minWidth: 400, idealWidth: 450, maxWidth: 600)
            .frame(minHeight: 300, idealHeight: 480)

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: chatView)
        panel.center()
    }

    private func createStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile", accessibilityDescription: "Hermes")
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }
        print("Menu bar set up")
    }

    @objc private func togglePanel() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Show Hermes", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        // Settings not yet implemented
    }

    private func registerGlobalHotkey() {
        // Option+Command+L to toggle
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let hasCommand = event.modifierFlags.contains(.command)
            let hasOption = event.modifierFlags.contains(.option)
            let isLKey = event.keyCode == 37  // 'L' key

            if hasCommand && hasOption && isLKey {
                DispatchQueue.main.async { [weak self] in
                    self?.togglePanel()
                }
            }
        }
    }
}
