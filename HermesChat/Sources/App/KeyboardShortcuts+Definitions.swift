import KeyboardShortcuts

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    /// Toggle the HermesChat floating panel
    static let togglePanel = Self(
        "togglePanel",
        default: KeyboardShortcuts.Shortcut(.l, modifiers: [.command, .option])
    )
}
