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

@MainActor
final class PreviewViewModel: ObservableObject {
    // Inputs
    let mainClipURL: URL
    let reactions: [EpisodeReaction]   // <-- Use your unified alias/type here (see note below)
    private let library: LibraryStore

    // User‑editable params
    @Published var mainChunkSec: Double = 8
    @Published var reactionChunkSec: Double = 6
    @Published private(set) var bleepMarksSec: [Double] = []

    // Live stitched preview
    @Published var previewItem: AVPlayerItem?

    // Export state
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    @Published var exportError: String?
    @Published var exportSuccessURL: URL?

    // We keep a reference so we can cancel
    private var exportSession: AVAssetExportSession?

    // MARK: Init
    init(mainClipURL: URL, reactions: [EpisodeReaction], library: LibraryStore) {
        self.mainClipURL = mainClipURL
        self.reactions = reactions
        self.library = library
        Task { rebuildPreview() }
    }

    // MARK: Live Preview
    func rebuildPreview() {
        Task {
            // Planner config
            var cfg = SegmentPlanner.Config()
            cfg.mainChunkSeconds = mainChunkSec
            cfg.reactionChunkSeconds = reactionChunkSec

            // bleep marks to CMTime (if your preview uses them)
            let ts: CMTimeScale = 600
            let bleeps = bleepMarksSec.map { CMTime(seconds: $0, preferredTimescale: ts) }

            // Build engine timeline
            let timeline = await SegmentPlanner.buildAlternatingTimeline(
                mainURL: mainClipURL,
                reactions: reactions,
                musicURL: nil,
                bleepMarks: bleeps,
                config: cfg
            )

            // Make a lightweight preview item
            do {
                let item = try await TimelinePreviewBuilder.makePlayerItem(
                    timeline: timeline,
                    options: .init(renderSize: .init(width: 1280, height: 720), frameRate: 30)
                )
                self.previewItem = item
            } catch {
                self.previewItem = nil
                self.exportError = error.localizedDescription
            }
        }
    }

    // MARK: Bleeps
    func addBleep(at seconds: Double) {
        let s = max(0, seconds)
        guard !bleepMarksSec.contains(where: { abs($0 - s) < 0.05 }) else { return }
        bleepMarksSec.append(s)
        bleepMarksSec.sort()
        rebuildPreview()
    }

    func removeBleep(at indexSet: IndexSet) {
        bleepMarksSec.remove(atOffsets: indexSet)
        rebuildPreview()
    }

    // MARK: Export
    func exportEpisode(seriesTitle: String = "My Show") {
        guard !isExporting else { return }
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportSuccessURL = nil

        Task {
            // Planner config
            var cfg = SegmentPlanner.Config()
            cfg.mainChunkSeconds = mainChunkSec
            cfg.reactionChunkSeconds = reactionChunkSec

            let ts: CMTimeScale = 600
            let bleeps: [CMTime] = bleepMarksSec.map { CMTime(seconds: $0, preferredTimescale: ts) }

            // Build engine timeline
            let timeline = await SegmentPlanner.buildAlternatingTimeline(
                mainURL: mainClipURL,
                reactions: reactions,
                musicURL: nil,
                bleepMarks: bleeps,
                config: cfg
            )

            // Compose
            let options = TimelineComposer.ExportOptions(
                renderSize: CGSize(width: 1280, height: 720),
                frameRate: 30,
                videoBitrate: 10_000_000
            )

            do {
                let session = try await TimelineComposer.makeExportSession(
                    timeline: timeline,
                    options: options
                )
                self.exportSession = session

                // Poll progress
                Task.detached { [weak session, weak self] in
                    while let s = session,
                          s.status == .waiting || s.status == .exporting {
                        let p = s.progress
                        await MainActor.run { self?.exportProgress = p }
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    }
                }

                // Run export
                session.exportAsynchronously { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isExporting = false
                        switch session.status {
                        case .completed:
                            let url = session.outputURL ?? FileManager.default.temporaryDirectory
                            self.exportSuccessURL = url
                            Task {
                                await self.postExportPersistAndSave(
                                    url: url,
                                    duration: timeline.duration.seconds,
                                    seriesTitle: seriesTitle
                                )
                            }
                        case .failed, .cancelled:
                            self.exportError = session.error?.localizedDescription ?? "Export failed."
                        default:
                            break
                        }
                    }
                }

            } catch {
                self.isExporting = false
                self.exportError = error.localizedDescription
            }
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
        isExporting = false
    }

    // MARK: Save + persist
    private func postExportPersistAndSave(url: URL,
                                          duration: Double,
                                          seriesTitle: String) async {
        let finalURL = library.moveExportIntoLibrary(url) ?? url

        // Photos
        let ok = await PermissionsService.ensurePhotosAddPermission()
        if ok {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: finalURL)
            }, completionHandler: { success, err in
                if let err { print("Save to Photos failed:", err.localizedDescription) }
            })
        }

        // Library
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
