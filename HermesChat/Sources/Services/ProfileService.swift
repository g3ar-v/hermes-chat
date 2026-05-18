//
//  ProfileService.swift
//  HermesChat
//
//  Created by John von neumann on 18/05/2026.
//

import Foundation

// MARK: - Hermes Profile

public struct HermesProfile: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String

    public var id: String { name }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

// MARK: - Profile Service

public final class ProfileService: Sendable {
    public static let shared = ProfileService()

    private let profilesRoot: String

    private init() {
        let home = NSHomeDirectory()
        profilesRoot = "\(home)/.hermes/profiles"
    }

    /// Scan the profiles directory and return all valid profile entries.
    /// A valid profile is a subdirectory containing a config.yaml.
    public func loadProfiles() -> [HermesProfile] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: profilesRoot) else {
            return []
        }
        return contents
            .filter { name in
                let configPath = "\(profilesRoot)/\(name)/config.yaml"
                return fm.fileExists(atPath: configPath)
            }
            .map { HermesProfile(name: $0, path: "\(profilesRoot)/\($0)") }
            .sorted { $0.name < $1.name }
    }

    /// The currently active profile name — from UserDefaults, falling back to
    /// the HERMES_HOME environment variable.
    public var activeProfileName: String {
        if let stored = UserDefaults.standard.string(forKey: "selectedProfile"),
           !stored.isEmpty {
            return stored
        }
        // Fallback: derive from HERMES_HOME env
        if let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"],
           let name = hermesHome.components(separatedBy: "/").last {
            return name
        }
        return "ezio" // sensible default
    }

    /// Persist the selected profile name.
    public func setActiveProfile(_ name: String) {
        UserDefaults.standard.set(name, forKey: "selectedProfile")
    }
}
