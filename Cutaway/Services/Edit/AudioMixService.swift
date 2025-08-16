//
//  AudioMixService.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import CoreMedia

/// Builds audio mix parameters for music bed + SFX (bleeps), with optional dialog ducking.
public struct AudioMixService {

    public struct Config {
        /// Music bed gain in dB (e.g. -18 dB).
        public var musicGainDb: Float = -18
        /// If `true`, briefly duck the music further under SFX.
        public var duckMusicDuringSFX: Bool = true
        /// Music duck amount in dB when SFX plays (e.g. -10 → an extra -10 dB).
        public var duckDeltaDb: Float = -10
        /// Duck fade in/out times.
        public var duckFadeSeconds: Double = 0.12

        public init() {}
    }

    public init() {}

    /// Create input parameters for the music bed track (loop/truncate already handled upstream).
    /// - Parameters:
    ///   - musicTrack: the composition track containing the music bed
    ///   - timelineDuration: total timeline length
    ///   - config: mix config
    ///   - sfxEvents: optional SFX time ranges to duck around
    public func makeMusicParameters(
        for musicTrack: AVCompositionTrack,
        timelineDuration: CMTime,
        config: Config = .init(),
        sfxEvents: [CMTimeRange] = []
    ) -> AVAudioMixInputParameters {
        let p = AVMutableAudioMixInputParameters(track: musicTrack)

        // Base level for the whole timeline
        p.setVolume(dbToLinear(config.musicGainDb), at: .zero)

        guard config.duckMusicDuringSFX, !sfxEvents.isEmpty else {
            return p
        }

        // Build simple duck envelopes around each SFX
        let ts: CMTimeScale = 600
        let fade = CMTime(seconds: max(0, config.duckFadeSeconds), preferredTimescale: ts)
        for ev in sfxEvents {
            // Times:
            // [--fadeIn-->][--fullDuck (event)-->][--fadeOut-->]
            let preStart = max(.zero, ev.start - fade)
            let postEnd  = min(timelineDuration, ev.end + fade)

            // Fade down into duck just before SFX
            p.setVolumeRamp(
                fromStartVolume: dbToLinear(config.musicGainDb),
                toEndVolume: dbToLinear(config.musicGainDb + config.duckDeltaDb),
                timeRange: CMTimeRange(start: preStart, end: ev.start)
            )
            // Hold duck level during the event
            p.setVolume(dbToLinear(config.musicGainDb + config.duckDeltaDb), at: ev.start)

            // Fade back up after SFX
            p.setVolumeRamp(
                fromStartVolume: dbToLinear(config.musicGainDb + config.duckDeltaDb),
                toEndVolume: dbToLinear(config.musicGainDb),
                timeRange: CMTimeRange(start: ev.end, end: postEnd)
            )
        }
        return p
    }

    /// Create parameters for a single SFX track (typically a short bleep).
    /// You usually make one SFX track per event you inserted into the composition.
    public func makeSFXParameters(for sfxTrack: AVCompositionTrack, gainDb: Float = 0) -> AVAudioMixInputParameters {
        let p = AVMutableAudioMixInputParameters(track: sfxTrack)
        p.setVolume(dbToLinear(gainDb), at: .zero)
        return p
    }

    // MARK: - Utils

    private func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }
}
