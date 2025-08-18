//
//  TimelinePreviewBuilder.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/17/25.
//

import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import CoreGraphics

public struct PreviewBuildOptions {
    public var renderSize: CGSize
    public var frameRate: Int32
    public init(renderSize: CGSize = .init(width: 1280, height: 720), frameRate: Int32 = 30) {
        self.renderSize = renderSize
        self.frameRate = frameRate
    }
}

/// Fast path preview of the stitched episode:
/// - 1 video + 1 audio track (dialog only)
/// - applies per-clip preferredTransform (keeps orientation)
/// - skips music/SFX and cross-dissolves (kept for final export)
public enum TimelinePreviewBuilder {

    public static func makePlayerItem(
        timeline: Timeline,
        options: PreviewBuildOptions = .init()
    ) async throws -> AVPlayerItem {

        let comp = AVMutableComposition()
        guard
            let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw NSError(domain: "PreviewBuilder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create tracks"])
        }

        var cursor: CMTime = .zero

        // Carry transforms over time
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)

        // Insert each clip in timeline order
        for clip in timeline.videoClips.sorted(by: { $0.at < $1.at }) {
            let asset = AVURLAsset(url: clip.url)

            // Modern async loads (Swift 6‑safe)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let transform = try await asset.load(.preferredTransform)

            guard let srcV = videoTracks.first else { continue }

            let srcRange = clip.source
            let dstRange = CMTimeRange(start: cursor, duration: srcRange.duration)

            try vTrack.insertTimeRange(srcRange, of: srcV, at: cursor)

            if let srcA = audioTracks.first {
                // best-effort; audio may be absent
                try? aTrack.insertTimeRange(srcRange, of: srcA, at: cursor)
            }

            // Apply orientation/content transform for this segment
            layerInstruction.setTransform(transform, at: dstRange.start)

            cursor = cursor + srcRange.duration
        }

        // Single instruction covering whole timeline
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        instruction.layerInstructions = [layerInstruction]

        let vComp = AVMutableVideoComposition()
        vComp.instructions = [instruction]
        vComp.renderSize = options.renderSize
        vComp.frameDuration = CMTime(value: 1, timescale: options.frameRate)

        // Create player item and assign videoComposition on the main actor.
        let item = await AVPlayerItem(asset: comp)
        await MainActor.run {
            item.videoComposition = vComp
        }
        return item        
    }
}
