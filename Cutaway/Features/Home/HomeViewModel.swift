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
        didSet { Task { await refreshMainMetadata() } }
    }
    
    /// Recorded reaction clips (front cam), in the order user added them.
    @Published private(set) var reactions: [ReactionClip] = []
    
    /// Derived metadata for UI (thumbnail/time, etc.)
    @Published private(set) var mainDurationSec: Double?
    @Published private(set) var mainFilename: String?
    
    /// Simple flags for UI routing
    @Published var showingPicker: Bool = false
    @Published var showingRecord: Bool = false
    
    /// Validation (ready to continue to Preview)
    var isReadyForPreview: Bool {
        mainClipURL != nil && reactions.count >= 1
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
        let name = (displayName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let defaultName = "Me"
        let clip = ReactionClip(url: url, displayName: name ?? defaultName)
        reactions.append(clip)
    }
    
    func renameReaction(id: UUID, to newName: String) {
        guard let idx = reactions.firstIndex(where: { $0.id == id }) else { return }
        reactions[idx].displayName = newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : newName
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
    
    /// Build a VM for the Preview screen (hand-off).
    func makePreviewViewModel() -> PreviewViewModel? {
        guard let mainURL = mainClipURL else { return nil }
        return PreviewViewModel(mainClipURL: mainURL, reactions: reactions)
    }
    
    // MARK: Private helpers
    
    private func refreshMainMetadata() async {
        guard let url = mainClipURL else { return }
        mainFilename = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            mainDurationSec = duration.seconds
        } catch {
            mainDurationSec = nil
        }
    }
}
