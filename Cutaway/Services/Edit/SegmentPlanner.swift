//
//  SegmentPlanner.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import CoreMedia


/// Builds an engine `Timeline` from simple, opinionated rules (alternating main/reaction chunks).
public enum SegmentPlanner {

    // MARK: Config

    public struct Config {
        public var targetDuration: Double = 60
        public var mainChunkSeconds: Double = 8
        public var reactionChunkSeconds: Double = 6
        public var dissolveSeconds: Double = 0.33
        public var lowerThirdSeconds: Double = 3
        public var musicGainDb: Float = -18.0
        public init() {}
    }

    public struct LowerThirdSpec {
        public let at: CMTime
        public let duration: CMTime
        public let text: String
        public let emoji: String
        public init(at: CMTime, duration: CMTime, text: String, emoji: String) {
            self.at = at; self.duration = duration; self.text = text; self.emoji = emoji
        }
    }

    // MARK: Build alternating engine timeline

    /// main (N sec) → reaction[i] (M sec) → main (N) → reaction[i+1] (M) → …
    public static func buildAlternatingTimeline(
        mainURL: URL,
        reactions: [EpisodeReaction],
        musicURL: URL? = nil,
        bleepMarks: [CMTime] = [],
        config: Config = .init()
    ) async -> Timeline {

        let ts: CMTimeScale = 600

        // Load durations
        let mainAsset = AVURLAsset(url: mainURL)
        let mainDuration = (try? await mainAsset.load(.duration)) ?? .zero
        let mainLen = mainDuration.seconds

        // Reaction assets + durations
        let reactionAssets: [(clip: EpisodeReaction, asset: AVURLAsset, duration: CMTime)] =
        await withTaskGroup(of: (EpisodeReaction, AVURLAsset, CMTime).self) { group in
            for rc in reactions {
                group.addTask {
                    let asset = AVURLAsset(url: rc.url)
                    let dur = (try? await asset.load(.duration)) ?? .zero
                    return (rc, asset, dur)
                }
            }
            var out: [(EpisodeReaction, AVURLAsset, CMTime)] = []
            for await x in group { out.append(x) }
            return out
        }

        // Early exit
        guard mainLen > 0, !reactionAssets.isEmpty else {
            return Timeline(videoClips: [], audioDialogClips: [], transitions: [], overlays: [],
                            musicBed: nil, sfx: [], duration: .zero)
        }

        // Build
        var video: [Clip] = []
        var dialog: [Clip] = []
        var overlays: [Overlay] = []
        var transitions: [Transition] = []

        var cursorTimeline: CMTime = .zero
        var cursorInMain: CMTime = .zero
        var reactionIndex = 0

        let target = CMTime(seconds: config.targetDuration, preferredTimescale: ts)
        let nMain = CMTime(seconds: config.mainChunkSeconds, preferredTimescale: ts)
        let mReaction = CMTime(seconds: config.reactionChunkSeconds, preferredTimescale: ts)
        let dissolve = CMTime(seconds: max(0, config.dissolveSeconds), preferredTimescale: ts)

        func clamp(_ t: CMTime, to max: CMTime) -> CMTime { t > max ? max : t }

        while cursorTimeline < target && cursorInMain < mainDuration {
            // MAIN slice
            let remainingMain = mainDuration - cursorInMain
            let remainingEpisode = target - cursorTimeline
            guard remainingMain > .zero, remainingEpisode > .zero else { break }

            let mainTake = clamp(nMain, to: min(remainingMain, remainingEpisode))
            let mainRange = CMTimeRange(start: cursorInMain, duration: mainTake)
            let mainClip = Clip(url: mainURL, mediaType: .video, source: mainRange, at: cursorTimeline)
            video.append(mainClip); dialog.append(mainClip)

            transitions.append(Transition(
                kind: .crossDissolve,
                range: CMTimeRange(start: max(.zero, cursorTimeline + mainTake - dissolve), duration: dissolve)
            ))

            cursorInMain = cursorInMain + mainTake
            cursorTimeline = cursorTimeline + mainTake
            if cursorTimeline >= target { break }

            // REACTION slice
            let (rc, _, rDur) = reactionAssets[reactionIndex]
            let take = clamp(mReaction, to: min(rDur, target - cursorTimeline))
            guard take > .zero else { break }

            let rRange = CMTimeRange(start: .zero, duration: take)
            let rClip = Clip(url: rc.url, mediaType: .video, source: rRange, at: cursorTimeline)
            video.append(rClip); dialog.append(rClip)

            // Lower‑third overlay at +1s
            let ltStart = cursorTimeline + CMTime(seconds: 1, preferredTimescale: ts)
            let ltDur = CMTime(seconds: config.lowerThirdSeconds, preferredTimescale: ts)
            overlays.append(Overlay(
                range: CMTimeRange(start: ltStart, duration: ltDur),
                payload: .lowerThird(text: rc.displayName, emoji: "🎤")
            ))

            transitions.append(Transition(
                kind: .crossDissolve,
                range: CMTimeRange(start: max(.zero, cursorTimeline + take - dissolve), duration: dissolve)
            ))

            cursorTimeline = cursorTimeline + take
            reactionIndex = (reactionIndex + 1) % reactionAssets.count
        }

        // Music (optional)
        let bedURL: URL? = musicURL
            ?? bundleURL(named: "music_bed", exts: ["mp3"])
            ?? bundleURL(named: "tvStatic", exts: ["mp3"])
        let bed = bedURL.map { AudioBed(url: $0, gainDb: config.musicGainDb) }

        // Bleeps
        var sfx: [AudioSFX] = []
        if !bleepMarks.isEmpty, let bleepURL = bundleURL(named: "bleep", exts: ["wav","mp3"]) {
            sfx = bleepMarks.map { AudioSFX(url: bleepURL, at: $0, gainDb: 0) }
        }

        return Timeline(
            videoClips: video,
            audioDialogClips: dialog,
            transitions: transitions,
            overlays: overlays,
            musicBed: bed,
            sfx: sfx,
            duration: cursorTimeline
        )
    }
}

// MARK: - File helpers

private func bundleURL(named name: String, exts: [String]) -> URL? {
    for ext in exts {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
    }
    return nil
}
