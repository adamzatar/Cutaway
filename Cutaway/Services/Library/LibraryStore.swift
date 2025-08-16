//
//  LibraryStore.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import AVFoundation
import UIKit

/// Observable library of all Series/Episodes, persisted as JSON in Documents.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var series: [Series] = []

    // MARK: - Lifecycle

    init() {
        load()
    }

    // MARK: - Public API

    /// Ensure a series exists (by title). Returns its id.
    @discardableResult
    func ensureSeries(_ title: String, emoji: String = "🎬") -> UUID {
        if let idx = series.firstIndex(where: { $0.title == title }) {
            return series[idx].id
        }
        let s = Series(title: title, emoji: emoji, episodes: [])
        series.insert(s, at: 0)
        save()
        return s.id
    }

    /// Add an episode to a series id (or create one if missing with `fallbackTitle`).
    func addEpisode(_ ep: Episode,
                    to seriesId: UUID,
                    fallbackTitle: String = "My Show",
                    emoji: String = "🎬") {
        if let idx = series.firstIndex(where: { $0.id == seriesId }) {
            series[idx].episodes.insert(ep, at: 0)
        } else {
            let s = Series(title: fallbackTitle, emoji: emoji, episodes: [ep])
            series.insert(s, at: 0)
        }
        save()
    }

    /// ✅ Backward‑compat overload (matches your previous signature).
    /// Internally forwards to the new `fallbackTitle` API.
    func addEpisode(_ ep: Episode,
                    to seriesId: UUID,
                    createIfMissing named: String? = nil,
                    emoji: String = "🎬") {
        addEpisode(ep, to: seriesId, fallbackTitle: named ?? "My Show", emoji: emoji)
    }

    /// Replace/update an episode by id within a series.
    func updateEpisode(_ ep: Episode, in seriesId: UUID) {
        guard let sIdx = series.firstIndex(where: { $0.id == seriesId }) else { return }
        if let eIdx = series[sIdx].episodes.firstIndex(where: { $0.id == ep.id }) {
            series[sIdx].episodes[eIdx] = ep
            save()
        }
    }

    /// Remove an episode by id. (We keep empty series; tweak if you prefer auto-delete.)
    func removeEpisode(id: UUID, in seriesId: UUID) {
        guard let sIdx = series.firstIndex(where: { $0.id == seriesId }) else { return }
        series[sIdx].episodes.removeAll { $0.id == id }
        save()
    }

    /// Rename a series (optionally update its emoji).
    func renameSeries(id: UUID, to newTitle: String, emoji: String? = nil) {
        guard let idx = series.firstIndex(where: { $0.id == id }) else { return }
        series[idx].title = newTitle
        if let emoji { series[idx].emoji = emoji }
        save()
    }

    /// Delete a whole series.
    func removeSeries(id: UUID) {
        series.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("library.json")
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            series = try JSONDecoder().decode([Series].self, from: data)
        } catch {
            series = [] // fresh start
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(series)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Library save error:", error)
        }
    }

    // MARK: - Extras (handy for Preview/Export flows)

    /// Move an exported mp4 into our Documents/Exports folder and return the new URL.
    func moveExportIntoLibrary(_ tempURL: URL) -> URL? {
        let dir = exportsDir()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("ep-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            print("Move export failed:", error)
            return nil
        }
    }

    /// Generate and persist a thumbnail JPEG for a video (async, iOS 16+).
    /// - Returns: File URL of JPEG, or nil if failed.
    func generateThumbnail(for videoURL: URL, at seconds: Double = 1.0) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 360)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        do {
            let cg = try await generateCGImageAsync(generator: gen, at: time)
            return try persistThumbnail(cgImage: cg)
        } catch {
            print("Thumb gen failed:", error)
            return nil
        }
    }

    /// Wraps AVAssetImageGenerator’s async callback API into async/await.
    private func generateCGImageAsync(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            let times = [NSValue(time: time)]
            generator.generateCGImagesAsynchronously(forTimes: times) { _, image, _, result, error in
                switch result {
                case .succeeded:
                    if let image = image {
                        cont.resume(returning: image)
                    } else {
                        cont.resume(throwing: NSError(domain: "LibraryStore",
                                                      code: -21,
                                                      userInfo: [NSLocalizedDescriptionKey: "Image nil on success"]))
                    }
                case .failed:
                    cont.resume(throwing: error ?? NSError(domain: "LibraryStore",
                                                           code: -22,
                                                           userInfo: [NSLocalizedDescriptionKey: "Thumbnail generation failed"]))
                case .cancelled:
                    cont.resume(throwing: NSError(domain: "LibraryStore",
                                                  code: -23,
                                                  userInfo: [NSLocalizedDescriptionKey: "Thumbnail generation cancelled"]))
                @unknown default:
                    cont.resume(throwing: NSError(domain: "LibraryStore",
                                                  code: -24,
                                                  userInfo: [NSLocalizedDescriptionKey: "Unknown generator result"]))
                }
            }
        }
    }

    /// Helper to write CGImage → JPEG file in thumbnails dir.
    private func persistThumbnail(cgImage: CGImage) throws -> URL {
        let ui = UIImage(cgImage: cgImage)
        guard let data = ui.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "LibraryStore", code: -20, userInfo: [NSLocalizedDescriptionKey: "JPEG conversion failed"])
        }
        let dir = thumbsDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Paths

    private func thumbsDir() -> URL {
        documentsDir().appendingPathComponent("thumbnails", isDirectory: true)
    }

    private func exportsDir() -> URL {
        documentsDir().appendingPathComponent("exports", isDirectory: true)
    }

    private func documentsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
