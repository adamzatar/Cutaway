//
//  LibraryStore.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var series: [Series] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("library.json")
    }()

    func load() {
        if let data = try? Data(contentsOf: url) {
            if let s = try? JSONDecoder().decode([Series].self, from: data) {
                series = s
            }
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(series)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Library save error:", error)
        }
    }

    func addEpisode(_ ep: Episode, to seriesId: UUID, createIfMissing named: String? = nil, emoji: String = "🎬") {
        if let idx = series.firstIndex(where: { $0.id == seriesId }) {
            series[idx].episodes.insert(ep, at: 0)
        } else {
            let new = Series(title: named ?? "My Show", emoji: emoji, episodes: [ep])
            series.insert(new, at: 0)
        }
        save()
    }

    func ensureSeries(_ title: String, emoji: String = "🎬") -> UUID {
        if let s = series.first(where: { $0.title == title }) { return s.id }
        let s = Series(title: title, emoji: emoji)
        series.insert(s, at: 0); save()
        return s.id
    }
}
