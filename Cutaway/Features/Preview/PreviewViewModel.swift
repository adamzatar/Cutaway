//
//  PreviewViewModel.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import SwiftUI
import Photos
import AVFoundation

@MainActor
final class PreviewViewModel: ObservableObject {
    var mainClipURL: URL
    var reactions: [ReactionClip] = []
    
    @Published var isExporting: Bool = false
    @Published var exportProgress: Float = 0
    @Published var exportError: String?
    @Published var exportSuccessURL: URL?
    
    private var currentExport: TimelineComposer.ExportHandle?
    
    init(mainClipURL: URL, reactions: [ReactionClip]) {
        self.mainClipURL = mainClipURL
        self.reactions = reactions
    }
    
    func exportEpisode() {
        Task {
            // 1) Plan segments (config-driven)
            var cfg = SegmentPlanner.Config()
            cfg.mainChunkSeconds = 8
            cfg.reactionChunkSeconds = 6
            let plan = await SegmentPlanner.buildAlternatingTimeline(
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
            let overlayRenderer: OverlayRendering = CaptionOverlayProvider()
            let overlayLayer = overlayRenderer.makeOverlayLayer(
                for: plan.overlays,
                renderSize: options.renderSize
            )

            // 4) Output URL
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cutaway-\(UUID().uuidString).mp4")

            // 5) Compose + export (composer will allocate tracks internally)
            let composer = TimelineComposer()
            isExporting = true
            exportProgress = 0
            exportError = nil
            exportSuccessURL = nil

            currentExport = composer.export(
                timeline: plan,
                to: outputURL,
                options: options,
                overlayLayer: overlayLayer,
                onProgress: { [weak self] p in
                    Task { @MainActor in self?.exportProgress = p }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        self?.isExporting = false
                        switch result {
                        case .success(let url):
                            self?.exportSuccessURL = url
                            self?.saveToPhotos(url: url)
                        case .failure(let err):
                            self?.exportError = err.localizedDescription
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
    
    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("No Photos add permission")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if let error = error {
                    print("Save to Photos failed:", error.localizedDescription)
                } else {
                    print("Saved to Photos")
                }
            }
        }
    }
}
