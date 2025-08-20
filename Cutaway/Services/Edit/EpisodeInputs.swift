//
//  EpisodeInputs.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import CoreGraphics

/// Tags a clip as video or audio. Keeps the model future-proof.
public enum MediaType { case video, audio }

/// A piece of media placed on the final timeline.
public struct Clip: Identifiable {
    public let id = UUID()                 // Stable identity for lists/diffs
    public let url: URL                    // Source file location
    public let mediaType: MediaType        // .video or .audio
    public let source: CMTimeRange         // Slice of the source asset to use
    public let at: CMTime                  // Start time on the final timeline
    public var preferredTransform: CGAffineTransform = .identity // For PiP/scale later

    public init(url: URL, mediaType: MediaType, source: CMTimeRange, at: CMTime) {
        self.url = url; self.mediaType = mediaType; self.source = source; self.at = at
    }

    public var duration: CMTime { source.duration }
    public var rangeOnTimeline: CMTimeRange { .init(start: at, duration: source.duration) }
}

/// Optional transition metadata (UI/analytics). Composer can infer dissolves from overlaps.
public struct Transition {
    public enum Kind { case crossDissolve }
    public let kind: Kind
    public let range: CMTimeRange          // When the transition happens on the timeline
    public init(kind: Kind, range: CMTimeRange) { self.kind = kind; self.range = range }
}

/// Anything drawn over video during a time range (lower-third, etc.).
public struct Overlay {
    public let range: CMTimeRange
    public let payload: OverlayPayload

    public enum OverlayPayload {
        case lowerThird(text: String, emoji: String)
    }

    public init(range: CMTimeRange, payload: OverlayPayload) {
        self.range = range; self.payload = payload
    }
}

/// Background music with gain in dB (e.g., -18 dB under dialog).
public struct AudioBed {
    public let url: URL
    public let gainDb: Float
    public init(url: URL, gainDb: Float) { self.url = url; self.gainDb = gainDb }
}

/// One-off sound effect placed at a specific timeline time.
public struct AudioSFX {
    public let url: URL
    public let at: CMTime
    public let gainDb: Float
    public init(url: URL, at: CMTime, gainDb: Float) {
        self.url = url; self.at = at; self.gainDb = gainDb
    }
}

/// The declarative recipe for an episode. Engine consumes this to export MP4.
public struct Timeline {
    public var videoClips: [Clip]              // All video clips
    public var audioDialogClips: [Clip]        // Dialog stems (often same as video clips’ audio)
    public var transitions: [Transition]       // Optional metadata for UI/rationales
    public var overlays: [Overlay]             // Core Animation overlays
    public var musicBed: AudioBed?             // Optional background music
    public var sfx: [AudioSFX]                 // Bleeps etc.
    public var duration: CMTime                // Total project length

    public init(videoClips: [Clip],
                audioDialogClips: [Clip],
                transitions: [Transition],
                overlays: [Overlay],
                musicBed: AudioBed?,
                sfx: [AudioSFX],
                duration: CMTime) {
        self.videoClips = videoClips
        self.audioDialogClips = audioDialogClips
        self.transitions = transitions
        self.overlays = overlays
        self.musicBed = musicBed
        self.sfx = sfx
        self.duration = duration
    }
}
