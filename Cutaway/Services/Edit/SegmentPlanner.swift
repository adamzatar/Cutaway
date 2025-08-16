//
//  SegmentPlanner.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import CoreMedia

/// Builds a Timeline from simple, opinionated rules (alternating main/reaction chunks).
/// Scales to N reactions and clamps to asset lengths + a target duration.
public enum SegmentPlanner {

    // MARK: Config

    public struct Config {
        public var targetDuration: Double = 60                 // seconds (episode cap)
        public var mainChunkSeconds: Double = 8                // N seconds of main
        public var reactionChunkSeconds: Double = 6            // M seconds of each reaction slice
        public var dissolveSeconds: Double = 0.33              // for UI marks; composer handles fades
        public var lowerThirdSeconds: Double = 3               // caption length when a reaction starts
        public var musicGainDb: Float = -18.0                  // matched with composer default

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

    // MARK: Entry point

    /// main (N sec) → reaction[i] (M sec) → main (N) → reaction[i+1] (M) → …
    public static func buildAlternatingTimeline(
        mainURL: URL,
        reactions: [ReactionClip],
        musicURL: URL? = nil,
        bleepMarks: [CMTime] = [],
        config: Config = .init()
    ) async -> Timeline {

        let ts: CMTimeScale = 600

        // ---- Load durations (async modern API) ----
        let mainAsset = AVURLAsset(url: mainURL)
        let mainDuration = (try? await mainAsset.load(.duration)) ?? CMTime(seconds: 0, preferredTimescale: ts)
        let mainLen = mainDuration.seconds

        // Reaction assets + durations
        let reactionAssets: [(clip: ReactionClip, asset: AVURLAsset, duration: CMTime)] = await withTaskGroup(of: (ReactionClip, AVURLAsset, CMTime).self) { group in
            for rc in reactions {
                group.addTask {
                    let asset = AVURLAsset(url: rc.url)
                    let dur = (try? await asset.load(.duration)) ?? .zero
                    return (rc, asset, dur)
                }
            }
            var out: [(ReactionClip, AVURLAsset, CMTime)] = []
            for await x in group { out.append(x) }
            return out
        }

        // ---- Early exit if no media ----
        guard mainLen > 0, !reactionAssets.isEmpty else {
            return Timeline(videoClips: [], audioDialogClips: [], transitions: [], overlays: [], musicBed: nil, sfx: [], duration: .zero)
        }

        // ---- Build alternating plan ----
        var video: [Clip] = []
        var dialog: [Clip] = []
        var overlays: [Overlay] = []
        var transitions: [Transition] = [] // optional; UI can highlight boundaries

        var cursorTimeline = CMTime.zero         // where we are in the OUTPUT (timeline)
        var cursorInMain = CMTime.zero           // where we are inside MAIN source
        var reactionIndex = 0

        let target = CMTime(seconds: config.targetDuration, preferredTimescale: ts)
        let nMain = CMTime(seconds: config.mainChunkSeconds, preferredTimescale: ts)
        let mReaction = CMTime(seconds: config.reactionChunkSeconds, preferredTimescale: ts)
        let dissolve = CMTime(seconds: max(0, config.dissolveSeconds), preferredTimescale: ts)

        func clamp(_ t: CMTime, to max: CMTime) -> CMTime { t > max ? max : t }

        // Alternate until we hit either the main’s end or the target duration
        while cursorTimeline < target && cursorInMain < mainDuration {
            // MAIN slice
            let remainingMain = mainDuration - cursorInMain
            let remainingInEpisode = target - cursorTimeline
            guard remainingMain > .zero, remainingInEpisode > .zero else { break }

            let mainTake = clamp(nMain, to: min(remainingMain, remainingInEpisode))
            let mainRangeInSrc = CMTimeRange(start: cursorInMain, duration: mainTake)
            let mainClip = Clip(url: mainURL, mediaType: .video, source: mainRangeInSrc, at: cursorTimeline)

            video.append(mainClip)
            dialog.append(mainClip)

            // Boundary note for UI (optional)
            transitions.append(Transition(
                kind: .crossDissolve,
                range: CMTimeRange(start: max(.zero, cursorTimeline + mainTake - dissolve), duration: dissolve)
            ))

            // advance cursors (explicit + avoids '+=' operator)
            cursorInMain = cursorInMain + mainTake
            cursorTimeline = cursorTimeline + mainTake
            if cursorTimeline >= target { break }

            // REACTION slice
            let (rc, _, rDur) = reactionAssets[reactionIndex]
            let take = clamp(mReaction, to: min(rDur, target - cursorTimeline))
            guard take > .zero else { break }

            // MVP: reaction starts at 0 (AI can shift later)
            let rRangeInSrc = CMTimeRange(start: .zero, duration: take)
            let rClip = Clip(url: rc.url, mediaType: .video, source: rRangeInSrc, at: cursorTimeline)

            video.append(rClip)
            dialog.append(rClip)

            // Lower‑third for this reaction at its start (appear at +1s)
            let lt = LowerThirdSpec(
                at: cursorTimeline + CMTime(seconds: 1, preferredTimescale: ts),
                duration: CMTime(seconds: config.lowerThirdSeconds, preferredTimescale: ts),
                text: rc.displayName,
                emoji: "🎤"
            )
            overlays.append(Overlay(range: CMTimeRange(start: lt.at, duration: lt.duration),
                                    payload: .lowerThird(text: lt.text, emoji: lt.emoji)))

            // Transition marker at the end of reaction (UI-only)
            transitions.append(Transition(
                kind: .crossDissolve,
                range: CMTimeRange(start: max(.zero, cursorTimeline + take - dissolve), duration: dissolve)
            ))

            // advance timeline
            cursorTimeline = cursorTimeline + take
            reactionIndex = (reactionIndex + 1) % reactionAssets.count
        }

        // ---- Music bed (optional) ----
        let bedURL: URL? = musicURL
            ?? Self.bundleURL(named: "music_bed", exts: ["mp3"])
            ?? Self.bundleURL(named: "tvStatic", exts: ["mp3"]) // alternative you added
        let bed = bedURL.map { AudioBed(url: $0, gainDb: config.musicGainDb) }

        // ---- SFX bleeps (try bleep.wav, fallback bleep.mp3) ----
        var sfx: [AudioSFX] = []
        if !bleepMarks.isEmpty, let bleepURL = Self.bundleURL(named: "bleep", exts: ["wav", "mp3"]) {
            sfx = bleepMarks.map { AudioSFX(url: bleepURL, at: $0, gainDb: 0) }
        }

        // ---- Final duration = how far the cursor advanced ----
        let finalDuration = cursorTimeline

        return Timeline(
            videoClips: video,
            audioDialogClips: dialog,
            transitions: transitions,
            overlays: overlays,
            musicBed: bed,
            sfx: sfx,
            duration: finalDuration
        )
    }

    // MARK: - Helpers

    /// Try multiple extensions for a given basename in the main bundle.
    private static func bundleURL(named name: String, exts: [String]) -> URL? {
        for ext in exts {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        return nil
    }
}
