//
//  Project.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation

/// A draft project you’re currently assembling (main video + reaction clips).
/// This is *not* the final exported Episode — it’s the working state used by Home/Preview.
public struct Project: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var mainURL: URL?                 // picked from Photos (copied to app-owned URL)
    public var reactions: [ReactionClip]     // recorded on device
    public var notes: String?                // optional (template choice, ideas, etc.)

    public init(id: UUID = UUID(),
                title: String = "Untitled",
                createdAt: Date = .now,
                mainURL: URL? = nil,
                reactions: [ReactionClip] = [],
                notes: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.mainURL = mainURL
        self.reactions = reactions
        self.notes = notes
    }

    /// Minimal readiness check for Preview.
    public var isReadyForPreview: Bool {
        mainURL != nil && !reactions.isEmpty
    }
}

/// A single reaction (front-camera) clip and its display name (caption).
public struct ReactionClip: Identifiable, Codable, Equatable {
    public let id: UUID
    public var url: URL
    public var displayName: String   // used for lower‑third caption

    public init(id: UUID = UUID(), url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
    }
}

// MARK: - Convenience mutations (nice for ViewModels)

public extension Project {
    mutating func setMain(url: URL) { self.mainURL = url }
    mutating func addReaction(url: URL, name: String = "Me") {
        reactions.append(ReactionClip(url: url, displayName: name))
    }
    mutating func renameReaction(id: UUID, to newName: String) {
        guard let i = reactions.firstIndex(where: { $0.id == id }) else { return }
        reactions[i].displayName = newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : newName
    }
    mutating func removeReaction(id: UUID) {
        reactions.removeAll { $0.id == id }
    }
}
