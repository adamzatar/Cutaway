//
//  BeatDetector.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/19/25.
//

import Foundation
import AVFoundation

enum BeatDetector {
    /// Very lightweight onset/“beat” detector:
    /// - downmixes to mono 32‑bit float @ 44.1k
    /// - computes short‑window average magnitude
    /// - peak‑picks against median with a minimum spacing
    static func detectBeats(url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)

        // Load first audio track
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        // Reader with linear PCM float output
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,  // interleaved mono
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = true   // ensure contiguous data

        guard reader.canAdd(output) else { return [] }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "BeatDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"])
        }

        // Window size ~23ms @ 44.1k
        let hop = 1024
        var energies: [Float] = []
        var totalSamples: Int64 = 0

        while reader.status == .reading, let sbuf = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sbuf) else { continue }

            // Get a contiguous pointer into the block
            var lenAtOffset = 0
            var totalLen    = 0
            var rawPtr: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: &lenAtOffset,
                totalLengthOut: &totalLen,
                dataPointerOut: &rawPtr
            )
            guard status == kCMBlockBufferNoErr, let rawPtr else { continue }

            // Number of Float32 samples available at this pointer
            let byteCount = lenAtOffset
            let sampleCount = byteCount / MemoryLayout<Float>.size

            let fptr = rawPtr.withMemoryRebound(to: Float.self, capacity: sampleCount) { $0 }

            // Simple average magnitude over hop-sized windows
            var i = 0
            while i + hop <= sampleCount {
                var e: Float = 0
                var j = 0
                while j < hop {
                    e += abs(fptr[i + j])
                    j += 1
                }
                energies.append(e / Float(hop))
                i += hop
            }

            totalSamples += Int64(sampleCount)
        }

        // Peak pick vs median with a min spacing
        guard !energies.isEmpty else { return [] }

        let sorted = energies.sorted()
        let median = sorted[sorted.count / 2]
        let threshold = median * 2.0

        var beats: [Double] = []
        let stepSec = Double(hop) / 44_100.0
        var lastBeatSec = -10.0

        for (idx, e) in energies.enumerated() where e > threshold {
            let t = Double(idx) * stepSec
            if t - lastBeatSec > 0.25 { // 250ms refractory
                beats.append(t)
                lastBeatSec = t
            }
        }

        return beats
    }
}
