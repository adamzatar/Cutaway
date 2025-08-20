//
//  TimelineComposer.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import CoreGraphics

/// Consumes the **engine** `Timeline` (EpisodeInputs.swift) and produces an export session.
public enum TimelineComposer {

    public struct ExportOptions {
        public var renderSize: CGSize
        public var frameRate: Int32
        public var videoBitrate: Int   // reserved for custom exporter; not used by AVAssetExportSession presets

        public init(renderSize: CGSize = .init(width: 1080, height: 1920),
                    frameRate: Int32 = 30,
                    videoBitrate: Int = 10_000_000) {
            self.renderSize = renderSize
            self.frameRate = frameRate
            self.videoBitrate = videoBitrate
        }
    }

    // dB → linear
    private static func dBToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    /// Builds the *final* export session from an engine `Timeline`.
    /// - Note: Cross‑dissolves/overlaps would require multiple video tracks; this MVP assumes
    ///         non‑overlapping clips. Transforms are applied at each clip start.
    public static func makeExportSession(
        timeline: Timeline,
        options: ExportOptions = .init()
    ) async throws -> AVAssetExportSession {

        // 1) Composition + tracks
        let comp = AVMutableComposition()

        guard
            let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let dialogTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw NSError(domain: "Composer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition tracks"])
        }

        // 2) Insert VIDEO segments (sorted by start time)
        for clip in timeline.videoClips.sorted(by: { $0.at < $1.at }) {
            let asset = AVURLAsset(url: clip.url)
            if let srcV = try await asset.loadTracks(withMediaType: .video).first {
                try vTrack.insertTimeRange(clip.source, of: srcV, at: clip.at)
            }
        }

        // 3) Insert DIALOG segments (sorted by start time)
        for clip in timeline.audioDialogClips.sorted(by: { $0.at < $1.at }) {
            let asset = AVURLAsset(url: clip.url)
            if let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                try dialogTrack.insertTimeRange(clip.source, of: srcA, at: clip.at)
            }
        }

        // 4) Optional SFX track
        var audioParams: [AVMutableAudioMixInputParameters] = []

        // Dialog params (flat 1.0)
        let dialogParams = AVMutableAudioMixInputParameters(track: dialogTrack)
        dialogParams.setVolume(1.0, at: .zero)
        audioParams.append(dialogParams)

        if !timeline.sfx.isEmpty,
           let sfxTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {

            let sfxParams = AVMutableAudioMixInputParameters(track: sfxTrack)

            for sfx in timeline.sfx {
                let asset = AVURLAsset(url: sfx.url)
                if let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                    let dur = try await asset.load(.duration)
                    try sfxTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: srcA, at: sfx.at)
                    sfxParams.setVolume(dBToLinear(sfx.gainDb), at: sfx.at)
                }
            }

            audioParams.append(sfxParams)
        }

        // 5) Video composition (basic)
        let vComp = AVMutableVideoComposition()
        vComp.renderSize = options.renderSize
        vComp.frameDuration = CMTime(value: 1, timescale: options.frameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: timeline.duration)

        // Single layer instruction with per‑clip transforms “stepped” at each clip start.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        for clip in timeline.videoClips.sorted(by: { $0.at < $1.at }) {
            if clip.preferredTransform != .identity {
                layerInstruction.setTransform(clip.preferredTransform, at: clip.at)
            }
        }
        instruction.layerInstructions = [layerInstruction]
        vComp.instructions = [instruction]

        // 6) Audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        // 7) Export session
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Composer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutaway-\(UUID().uuidString).mp4")

        export.outputURL = outURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.videoComposition = vComp
        export.audioMix = audioMix

        return export
    }
}

// MARK: - Small helpers

private extension CMTime {
    static func milliseconds(_ ms: Int) -> CMTime {
        CMTime(value: CMTimeValue(ms), timescale: 1000)
    }
}
