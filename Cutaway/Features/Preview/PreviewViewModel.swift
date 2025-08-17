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
@MainActor
final class PreviewViewModel: ObservableObject {
    // Inputs
    let mainClipURL: URL
    let reactions: [ReactionClip]
    private let library: LibraryStore

    // UI state
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    @Published var exportError: String?
    @Published var exportSuccessURL: URL?

    private var currentExport: TimelineComposer.ExportHandle?

    init(mainClipURL: URL, reactions: [ReactionClip], library: LibraryStore) {
        self.mainClipURL = mainClipURL
        self.reactions = reactions
        self.library = library
    }

    /// Build timeline, render, save, persist.
    func exportEpisode(seriesTitle: String = "My Show") {
        guard !isExporting else { return }
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportSuccessURL = nil

        Task {
            do {
                // 1) Build timeline (8s main / 6s reaction alternating)
                var cfg = SegmentPlanner.Config()
                cfg.mainChunkSeconds = 8
                cfg.reactionChunkSeconds = 6
                let timeline = await SegmentPlanner.buildAlternatingTimeline(
                    mainURL: mainClipURL,
                    reactions: reactions,
                    musicURL: nil,
                    bleepMarks: [],
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

                                Task {
                                    await self.postExportPersistAndSave(
                                        url: url,
                                        duration: timeline.duration.seconds,
                                        seriesTitle: seriesTitle
                                    )
                                }
                            case .failure(let err):
                                self.exportError = err.localizedDescription
                            }
                        }
                    }
                )
            } 
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
        library.addEpisode(episode, to: seriesId, fallbackTitle: seriesTitle, emoji: "📺")
    }

    private func makeAutoEpisodeTitle() -> String {
        "Episode \(Int.random(in: 100...999))"
    }
}
