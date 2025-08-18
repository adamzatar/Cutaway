//
//  PreviewViewModel.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import SwiftUI
import AVFoundation
import Photos

/// Orchestrates: plan → compose → export → save to Photos → persist to Library.
/// Also owns user-editable params (segment lengths + bleep marks) and a live stitched preview.
@MainActor
final class PreviewViewModel: ObservableObject {
    // Inputs
    let mainClipURL: URL
    let reactions: [ReactionClip]
    private let library: LibraryStore

    // User‑editable params
    @Published var mainChunkSec: Double = 8          // N seconds of main
    @Published var reactionChunkSec: Double = 6      // M seconds of reaction
    @Published private(set) var bleepMarksSec: [Double] = []  // seconds on the final timeline

    // Live stitched preview (alternating main ↔ reaction)
    @Published var previewItem: AVPlayerItem?

    // Export state
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    @Published var exportError: String?
    @Published var exportSuccessURL: URL?

    private var currentExport: TimelineComposer.ExportHandle?

    // MARK: - Init

    init(mainClipURL: URL, reactions: [ReactionClip], library: LibraryStore) {
        self.mainClipURL = mainClipURL
        self.reactions = reactions
        self.library = library
        // Build initial live preview
        Task { rebuildPreview() }
    }

    // MARK: - Live Preview

    /// Build a fast, stitched AVPlayerItem for the UI preview.
    /// Skips heavy parts (music/SFX/cross-dissolves) for speed. Final export still includes them.
    func rebuildPreview() {
        Task {
            // 1) Build timeline from current params
            var cfg = SegmentPlanner.Config()
            cfg.mainChunkSeconds = mainChunkSec
            cfg.reactionChunkSeconds = reactionChunkSec

            // Convert bleep seconds to CMTime (planner needs these to mark SFX)
            let ts: CMTimeScale = 600
            let bleeps = bleepMarksSec.map { CMTime(seconds: $0, preferredTimescale: ts) }

            let timeline = await SegmentPlanner.buildAlternatingTimeline(
                mainURL: mainClipURL,
                reactions: reactions,
                musicURL: nil,
                bleepMarks: bleeps,
                config: cfg
            )

            // 2) Build an AVPlayerItem for preview
            do {
                let item = try await TimelinePreviewBuilder.makePlayerItem(timeline: timeline,
                                                                           options: .init())
                // Publish to UI
                self.previewItem = item
            } catch {
                self.previewItem = nil
                self.exportError = error.localizedDescription
            }
        }
    }

    // MARK: - Bleeps

    func addBleep(at seconds: Double) {
        let s = max(0, seconds)
        guard !bleepMarksSec.contains(where: { abs($0 - s) < 0.05 }) else { return } // dedupe ~50ms
        bleepMarksSec.append(s)
        bleepMarksSec.sort()
        // Rebuild preview so user hears positions reflected in the stitched timing (SFX is export-only, but timeline bounds shift)
        rebuildPreview()
    }

    func removeBleep(at indexSet: IndexSet) {
        bleepMarksSec.remove(atOffsets: indexSet)
        rebuildPreview()
    }

    // MARK: - Export

    /// Build timeline, render, save, persist.
    func exportEpisode(seriesTitle: String = "My Show") {
        guard !isExporting else { return }
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportSuccessURL = nil

        Task {
            // 1) Build timeline using current params
            var cfg = SegmentPlanner.Config()
            cfg.mainChunkSeconds = mainChunkSec
            cfg.reactionChunkSeconds = reactionChunkSec

            let ts: CMTimeScale = 600
            let bleeps: [CMTime] = bleepMarksSec.map { CMTime(seconds: $0, preferredTimescale: ts) }

            let timeline = await SegmentPlanner.buildAlternatingTimeline(
                mainURL: mainClipURL,
                reactions: reactions,
                musicURL: nil,
                bleepMarks: bleeps,
                config: cfg
            )

            // 2) Export options
            let options = TimelineComposer.ExportOptions(
                presetName: AVAssetExportPreset1280x720,
                frameRate: 30,
                renderSize: CGSize(width: 1280, height: 720),
                dissolveSeconds: 0.33,
                musicGainDb: -18
            )

            // 3) Overlays
            let overlayLayer = CaptionOverlayProvider()
                .makeOverlayLayer(for: timeline.overlays, renderSize: options.renderSize)

            // 4) Output URL
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cutaway-\(UUID().uuidString).mp4")

            // 5) Compose + export
            let composer = TimelineComposer()
            currentExport = composer.export(
                timeline: timeline,
                to: outputURL,
                options: options,
                overlayLayer: overlayLayer,
                onProgress: { [weak self] p in
                    Task { @MainActor in self?.exportProgress = p }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isExporting = false
                        switch result {
                        case .success(let url):
                            self.exportSuccessURL = url
                            Task { await self.postExportPersistAndSave(url: url,
                                                                       duration: timeline.duration.seconds,
                                                                       seriesTitle: seriesTitle) }
                        case .failure(let err):
                            self.exportError = err.localizedDescription
                        }
                    }
                }
            )
        }
    }

    func cancelExport() {
        currentExport?.cancel()
        isExporting = false
    }

    // MARK: - Post export: move file, save to Photos, persist to Library

    private func postExportPersistAndSave(url: URL,
                                          duration: Double,
                                          seriesTitle: String) async {
        // Move the temp file into our Documents/exports (so we own it)
        let finalURL = library.moveExportIntoLibrary(url) ?? url

        // Photos add-only permission + save
        let ok = await PermissionsService.ensurePhotosAddPermission()
        if ok {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: finalURL)
            }) { success, err in
                if let err { print("Save to Photos failed:", err.localizedDescription) }
            }
        }

        // Thumbnail + persist to Library
        let thumbURL = await library.generateThumbnail(for: finalURL, at: 1.0)
        let seriesId = library.ensureSeries(seriesTitle, emoji: "📺")
        let episode = Episode(
            title: makeAutoEpisodeTitle(),
            durationSec: duration,
            exportURL: finalURL,
            createdAt: .now,
            thumbnailURL: thumbURL,
            templateTag: "Default"
        )
        // Disambiguated overload with fallback title (matches your LibraryStore)
        library.addEpisode(episode, to: seriesId, fallbackTitle: seriesTitle, emoji: "📺")
    }

    private func makeAutoEpisodeTitle() -> String {
        "Episode \(Int.random(in: 100...999))"
    }
}
