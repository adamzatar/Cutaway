//
//  EpisodePlan.swift
//  Cutaway
//
//  Engine-side model (what the exporter/preview consumes).
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia

/// The one-and-only “reaction clip” model the app uses.
public struct EpisodeReaction: Identifiable, Codable, Equatable {
    public let id: UUID
    public var url: URL
    public var displayName: String
    /// If we detected the clap transient, store it: positive = reaction lags main.
    public var detectedOffsetSec: Double?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        detectedOffsetSec: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.detectedOffsetSec = detectedOffsetSec
    }
}

/// TEMP back‑compat so older call sites using `ReactionClip` still compile.
/// You can delete this typealias once you’ve replaced all references.
public typealias ReactionClip = EpisodeReaction

public struct BleepMark: Hashable {
    public var atSec: Double
    public init(_ s: Double) { self.atSec = s }
}

/// The lightweight “edit intent” the UI collects before we build the engine timeline.
public struct EpisodePlan {
    public var mainURL: URL
    public var reactions: [EpisodeReaction]
    public var mainChunkSec: Double
    public var reactChunkSec: Double
    public var beatSnap: Bool
    public var bleepMarks: [BleepMark]
    public var layoutMode: LayoutMode

    public enum LayoutMode: String, Codable{
        case autoAlternate        // A/B alternate, sprinkle split
        case alwaysSplit          // dual side-by-side
        case mainWithPictureInPic // main full, small reaction PiP
    }

    public init(
        mainURL: URL,
        reactions: [EpisodeReaction],
        mainChunkSec: Double = 6,
        reactChunkSec: Double = 4,
        beatSnap: Bool = false,
        bleepMarks: [BleepMark] = [],
        layoutMode: LayoutMode = .autoAlternate
    ) {
        self.mainURL = mainURL
        self.reactions = reactions
        self.mainChunkSec = mainChunkSec
        self.reactChunkSec = reactChunkSec
        self.beatSnap = beatSnap
        self.bleepMarks = bleepMarks
        self.layoutMode = layoutMode
    }
}
