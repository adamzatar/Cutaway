//
//  TrackAllocator.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation

/// Pairing of a logical clip and the physical track index it should use.
public struct AllocatedClip {
    public let clip: Clip
    public let trackIndex: Int
}

/// Result of allocating all video clips to physical tracks.
public struct AllocationResult {
    public let allocatedVideo: [AllocatedClip]
    public let trackCount: Int
}

/// Greedy interval-graph coloring: assign the minimum number of tracks
/// such that clips that overlap in *timeline time* don't share a track.
public final class TrackAllocator {

    public init() {}

    /// Assigns each *video* clip a physical track index.
    /// - Parameter clips: All video `Clip`s on the timeline (ignore pure-audio clips).
    /// - Returns: Mapping + how many tracks to create in AVMutableComposition.
    public func allocateVideoTracks(_ clips: [Clip]) -> AllocationResult {
        // Sort by timeline start so we can greedily reuse the earliest-free track.
        let sorted = clips.sorted { a, b in
            a.rangeOnTimeline.start < b.rangeOnTimeline.start
        }

        // For each physical track, remember the *end time* of the last clip we placed there.
        // If endTime <= newClip.at, that track is free for reuse.
        var trackEndTimes: [CMTime] = []                 // index -> end time
        var out: [AllocatedClip] = []

        for c in sorted {
            // Find first track whose last clip ends *at or before* this clip's start (no overlap).
            var assigned: Int? = nil
            for (i, endTime) in trackEndTimes.enumerated() {
                if endTime <= c.at {
                    assigned = i
                    break
                }
            }

            if let idx = assigned {
                // Reuse track i; extend its end time to this clip's end.
                trackEndTimes[idx] = c.rangeOnTimeline.end
                out.append(AllocatedClip(clip: c, trackIndex: idx))
            } else {
                // No track free ⇒ make a new one.
                trackEndTimes.append(c.rangeOnTimeline.end)
                let newIndex = trackEndTimes.count - 1
                out.append(AllocatedClip(clip: c, trackIndex: newIndex))
            }
        }

        return AllocationResult(allocatedVideo: out, trackCount: trackEndTimes.count)
    }
}
