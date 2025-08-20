//
//  Project.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import Foundation

/// Lightweight persistence model for an in‑progress episode.
/// (Separate from the engine Timeline.)
public struct Project: Codable, Equatable {
    /// Picked main video URL (optional until the user chooses one)
    public var mainURL: URL?

    /// Recorded reaction clips (front/back camera), in user order.
    public var reactions: [EpisodeReaction] = []

    // MARK: - Mutating API

    /// Set/replace the main video.
    public mutating func setMain(url: URL) {
        self.mainURL = url
    }

    /// Add a reaction clip with an optional display name.
    public mutating func addReaction(url: URL, displayName: String? = nil) {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Me"
        reactions.append(EpisodeReaction(url: url, displayName: name))
    }

    /// Rename a reaction by id.
    public mutating func renameReaction(id: UUID, to newName: String) {
        guard let idx = reactions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        reactions[idx].displayName = trimmed.nilIfEmpty ?? "Guest"
    }

    /// Remove a reaction by id.
    public mutating func removeReaction(id: UUID) {
        reactions.removeAll { $0.id == id }
    }

    /// Clear everything.
    public mutating func clearAll() {
        mainURL = nil
        reactions.removeAll()
    }
}

// Small helper
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
