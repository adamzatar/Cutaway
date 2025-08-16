//
//  TimelineComposer.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import UIKit   // CALayer / Core Animation
import CoreMedia

/// Turns a `Timeline` into an MP4 export with dissolves, music, SFX, and (optionally) an injected overlay layer.
/// - Scales to N overlapping clips (via TrackAllocator).
/// - iOS 18+: uses `states(updateInterval:)` + `export(to:as:)`.
/// - iOS 16–17: legacy selector-based coordinator (no deprecated `status`/`error` usage).
public final class TimelineComposer {

    public init() {}

    // MARK: Public API

    public struct ExportOptions {
        public var presetName: String
        public var frameRate: Int32
        public var renderSize: CGSize
        public var dissolveSeconds: Double
        public var musicGainDb: Float

        public init(presetName: String = AVAssetExportPreset1280x720,
                    frameRate: Int32 = 30,
                    renderSize: CGSize = CGSize(width: 1280, height: 720),
                    dissolveSeconds: Double = 0.33,
                    musicGainDb: Float = -18.0) {
            self.presetName = presetName
            self.frameRate = frameRate
            self.renderSize = renderSize
            self.dissolveSeconds = dissolveSeconds
            self.musicGainDb = musicGainDb
        }
    }

    /// Handle to allow cancellation from UI.
    public final class ExportHandle {
        fileprivate var session: AVAssetExportSession?
        fileprivate var task: Task<Void, Never>?
        public func cancel() {
            task?.cancel()
            session?.cancelExport()
        }
    }

    /// Build & export the episode.
    @discardableResult
    public func export(timeline: Timeline,
                       to outputURL: URL,
                       options: ExportOptions = .init(),
                       overlayLayer: CALayer? = nil,
                       onProgress: @escaping (Float) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) -> ExportHandle {

        let handle = ExportHandle()

        handle.task = Task {
            do {
                // 1) Allocate tracks & build AV graph
                let allocation = TrackAllocator().allocateVideoTracks(timeline.videoClips)
                let (composition, videoComposition, audioMix) = try await buildAVGraph(
                    timeline: timeline,
                    allocation: allocation,
                    options: options,
                    overlayLayer: overlayLayer
                )

                // 2) Configure export session
                guard let session = AVAssetExportSession(asset: composition, presetName: options.presetName) else {
                    throw NSError(domain: "TimelineComposer", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetExportSession"])
                }
                handle.session = session

                try? FileManager.default.removeItem(at: outputURL)
                session.outputURL = outputURL
                session.outputFileType = .mp4
                session.videoComposition = videoComposition
                session.audioMix = audioMix
                session.shouldOptimizeForNetworkUse = true

                // 3) Export: modern vs legacy
                if #available(iOS 18.0, *) {
                    // Progress via states(...)
                    let progressTask = Task {
                        for await state in session.states(updateInterval: 0.1) {
                            if Task.isCancelled { break }
                            switch state {
                            case .pending, .waiting:
                                onProgress(0)
                            case .exporting(let progress):
                                onProgress(Float(progress.fractionCompleted))
                            @unknown default:
                                break
                            }
                        }
                    }
                    // Completion via export(to:as:)
                    do {
                        try await session.export(to: outputURL, as: .mp4)
                        progressTask.cancel()
                        completion(.success(outputURL))
                    } catch {
                        progressTask.cancel()
                        completion(.failure(error))
                    }
                } else {
                    // iOS 16–17: selector-based coordinator (no @Sendable captures; no deprecated status/error reads)
                    await LegacyExportCoordinator.run(
                        session: session,
                        outputURL: outputURL,
                        onProgress: onProgress,
                        completion: completion
                    )
                }
            } catch {
                completion(.failure(error))
            }
        }

        return handle
    }

    // MARK: - Build graph with async AVAsset loading

    private func buildAVGraph(timeline: Timeline,
                              allocation: AllocationResult,
                              options: ExportOptions,
                              overlayLayer: CALayer?)
    async throws -> (AVMutableComposition, AVMutableVideoComposition, AVMutableAudioMix) {

        let comp = AVMutableComposition()

        // A) Create physical video tracks
        var vTracks: [AVMutableCompositionTrack] = []
        for _ in 0..<allocation.trackCount {
            if let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                vTracks.append(t)
            }
        }

        // B) Insert video slices per allocated track (async tracks + preferredTransform)
        for a in allocation.allocatedVideo {
            if Task.isCancelled { throw CancellationError() }
            let asset = AVURLAsset(url: a.clip.url)
            let srcVs = try await asset.loadTracks(withMediaType: .video)
            guard let srcV = srcVs.first else { continue }

            try vTracks[a.trackIndex].insertTimeRange(a.clip.source, of: srcV, at: a.clip.at)

            let srcTransform = try await srcV.load(.preferredTransform)
            vTracks[a.trackIndex].preferredTransform = srcTransform.concatenating(a.clip.preferredTransform)
        }

        // C) Dialog audio
        if let dialogTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            for clip in timeline.audioDialogClips {
                if Task.isCancelled { throw CancellationError() }
                let asset = AVURLAsset(url: clip.url)
                if let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                    try dialogTrack.insertTimeRange(clip.source, of: srcA, at: clip.at)
                }
            }
        }

        // D) Music bed (loop/truncate)
        var mixParams: [AVAudioMixInputParameters] = []
        if let bed = timeline.musicBed {
            let bedAsset = AVURLAsset(url: bed.url)
            if let src = try await bedAsset.loadTracks(withMediaType: .audio).first,
               let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {

                let bedDur = try await bedAsset.load(.duration)
                var cursor = CMTime.zero
                while cursor < timeline.duration {
                    if Task.isCancelled { throw CancellationError() }
                    let remain = timeline.duration - cursor
                    let take = min(remain, bedDur)
                    try mTrack.insertTimeRange(.init(start: .zero, duration: take), of: src, at: cursor)
                    cursor = cursor + take
                }

                let p = AVMutableAudioMixInputParameters(track: mTrack)
                p.setVolume(dbToLinear(options.musicGainDb), at: .zero)
                mixParams.append(p)
            }
        }

        // E) SFX
        for s in timeline.sfx {
            if Task.isCancelled { throw CancellationError() }
            let a = AVURLAsset(url: s.url)
            if let src = try await a.loadTracks(withMediaType: .audio).first,
               let sTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let sfxDur = try await a.load(.duration)
                try sTrack.insertTimeRange(.init(start: .zero, duration: sfxDur), of: src, at: s.at)
                let p = AVMutableAudioMixInputParameters(track: sTrack)
                p.setVolume(dbToLinear(s.gainDb), at: s.at)
                mixParams.append(p)
            }
        }

        // F) Video composition (fps/size + per-track opacity ramps)
        let vComp = AVMutableVideoComposition()
        vComp.renderSize = options.renderSize
        vComp.frameDuration = CMTime(value: 1, timescale: options.frameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: timeline.duration)
        instruction.layerInstructions = buildLayerInstructions(
            videoTracks: vTracks,
            allocation: allocation,
            dissolveSeconds: options.dissolveSeconds
        )
        vComp.instructions = [instruction]

        // G) Attach injected overlays (if provided)
        if let overlayLayer {
            let parent = CALayer()
            let videoLayer = CALayer()
            parent.frame = CGRect(origin: .zero, size: options.renderSize)
            videoLayer.frame = parent.frame
            parent.isGeometryFlipped = true
            parent.addSublayer(overlayLayer)

            vComp.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parent
            )
        }

        // H) Audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParams

        return (comp, vComp, audioMix)
    }

    // MARK: - Dissolve layer instructions

    private func buildLayerInstructions(videoTracks: [AVMutableCompositionTrack],
                                        allocation: AllocationResult,
                                        dissolveSeconds: Double) -> [AVVideoCompositionLayerInstruction] {
        var out: [AVVideoCompositionLayerInstruction] = []
        let dissolve = CMTime(seconds: max(0, dissolveSeconds), preferredTimescale: 600)

        for (idx, track) in videoTracks.enumerated() {
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            li.setOpacity(0, at: .zero)

            let clipsOnTrack = allocation.allocatedVideo.filter { $0.trackIndex == idx }.map { $0.clip }
            for clip in clipsOnTrack {
                let start = clip.at
                let end   = clip.at + clip.duration

                // Fade in
                let inEnd = min(start + dissolve, end)
                if inEnd > start {
                    li.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1,
                                      timeRange: CMTimeRange(start: start, end: inEnd))
                } else {
                    li.setOpacity(1, at: start)
                }

                // Fade out
                let outStart = max(end - dissolve, start)
                if end > outStart {
                    li.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0,
                                      timeRange: CMTimeRange(start: outStart, end: end))
                } else {
                    li.setOpacity(0, at: end)
                }
            }
            out.append(li)
        }
        return out
    }

    // MARK: - Legacy coordinator (iOS 16–17 only; avoids deprecated API reads)

    /// Selector‑based legacy export helper.
    /// Marked **deprecated** (not obsoleted) on iOS 18 so it can still be referenced behind `#unavailable(iOS 18.0)`.
    @available(iOS, introduced: 11.0, deprecated: 18.0, message: "Use states(updateInterval:) + export(to:as:) on iOS 18+.")
    @MainActor
    private final class LegacyExportCoordinator: NSObject {
        private weak var session: AVAssetExportSession?
        private var timer: Timer?
        private let outputURL: URL
        private let onProgress: (Float) -> Void
        private let completion: (Result<URL, Error>) -> Void

        init(session: AVAssetExportSession,
             outputURL: URL,
             onProgress: @escaping (Float) -> Void,
             completion: @escaping (Result<URL, Error>) -> Void) {
            self.session = session
            self.outputURL = outputURL
            self.onProgress = onProgress
            self.completion = completion
        }

        func start() {
            // Progress polling on main runloop (selector avoids @Sendable capture).
            timer = Timer.scheduledTimer(timeInterval: 0.1,
                                         target: self,
                                         selector: #selector(tick),
                                         userInfo: nil,
                                         repeats: true)

            // Completion (no reads of deprecated `status` / `error`)
            session?.exportAsynchronously { [weak self] in
                DispatchQueue.main.async { self?.finish() }
            }
        }

        @objc private func tick() {
            guard let s = session else { timer?.invalidate(); return }
            onProgress(s.progress)
            // Stop polling when progress reports complete
            if s.progress >= 1.0 { timer?.invalidate() }
        }

        private func finish() {
            timer?.invalidate()
            // Treat success as "output file exists", otherwise failure.
            if FileManager.default.fileExists(atPath: outputURL.path) {
                completion(.success(outputURL))
            } else {
                completion(.failure(NSError(domain: "TimelineComposer",
                                            code: -13,
                                            userInfo: [NSLocalizedDescriptionKey: "Export failed"])))
            }
        }

        /// Convenience runner for the composer.
        @MainActor
        static func run(session: AVAssetExportSession,
                        outputURL: URL,
                        onProgress: @escaping (Float) -> Void,
                        completion: @escaping (Result<URL, Error>) -> Void) async {
            let c = LegacyExportCoordinator(session: session,
                                            outputURL: outputURL,
                                            onProgress: onProgress,
                                            completion: completion)
            c.start()
        }
    }

    // MARK: - Utils

    private func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }
}
