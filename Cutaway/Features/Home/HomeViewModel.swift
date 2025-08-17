//
//  HomeViewModel.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation

/// Owns the user's in‑progress episode selection:
/// - main clip (picked from Photos)
/// - reaction clips (recorded on device)
/// - simple utilities: rename/delete reaction, clear project, validate ready state
@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: Inputs / State

    /// Picked main video URL (app‑owned file from MediaPicker).
    @Published var mainClipURL: URL? {
        didSet {
            // Avoid duplicate work if URL didn't actually change
            guard mainClipURL != oldValue else { return }
            Task { await refreshMainMetadata() }
        }
    }

    /// Recorded reaction clips (front cam), in the order user added them.
    @Published private(set) var reactions: [ReactionClip] = []

    /// Derived metadata for UI (thumbnail/time, etc.)
    @Published private(set) var mainDurationSec: Double?
    @Published private(set) var mainFilename: String?

    /// Simple flags for UI routing
    @Published var showingPicker: Bool = false
    @Published var showingRecord: Bool = false

    /// MVP cap (change if you want more)
    private let maxReactions = 3

    /// Validation (ready to continue to Preview)
    var isReadyForPreview: Bool {
        mainClipURL != nil && !reactions.isEmpty
    }

    // MARK: Init

    init(mainClipURL: URL? = nil, reactions: [ReactionClip] = []) {
        self.mainClipURL = mainClipURL
        self.reactions = reactions
        if mainClipURL != nil {
            Task { await refreshMainMetadata() }
        }
    }

    // MARK: Public API (called by Views)

    func setMainClip(url: URL) {
        mainClipURL = url
    }

    func addReaction(url: URL, displayName: String? = nil) {
        // Respect the MVP cap; you can remove this guard to allow unlimited
        guard reactions.count < maxReactions else { return }
        let name = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Me"
        reactions.append(ReactionClip(url: url, displayName: name))
    }

    func renameReaction(id: UUID, to newName: String) {
        guard let idx = reactions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        reactions[idx].displayName = trimmed.isEmpty ? "Guest" : trimmed
    }

    func removeReaction(id: UUID) {
        reactions.removeAll { $0.id == id }
    }

    func clearAll() {
        mainClipURL = nil
        reactions.removeAll()
        mainDurationSec = nil
        mainFilename = nil
    }

    /// Build a VM for the Preview screen (hand‑off).
    func makePreviewViewModel(library: LibraryStore) -> PreviewViewModel? {
        guard let mainURL = mainClipURL else { return nil }
        return PreviewViewModel(mainClipURL: mainURL, reactions: reactions, library: library)
    }

    // MARK: Private helpers

    private func refreshMainMetadata() async {
        guard let url = mainClipURL else { return }
        mainFilename = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            // Be defensive: sometimes zero/invalid sneaks in from odd files
            if duration.isValid, duration.isNumeric, duration.seconds > 0 {
                mainDurationSec = duration.seconds
            } else {
                mainDurationSec = nil
            }
        } catch {
            mainDurationSec = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
