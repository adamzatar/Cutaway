//
//  Library.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation

public struct Series: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var emoji: String
    public var episodes: [Episode]          // newest first is fine
    public init(id: UUID = UUID(), title: String, emoji: String, episodes: [Episode] = []) {
        self.id = id; self.title = title; self.emoji = emoji; self.episodes = episodes
    }
}

public struct Episode: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var durationSec: Double
    public var exportURL: URL                // final mp4 in app-owned folder
    public var createdAt: Date
    public var thumbnailURL: URL?            // generated frame
    public var templateTag: String           // "Trip", "Roast", "Game", etc.
    public init(id: UUID = UUID(), title: String, durationSec: Double, exportURL: URL,
                createdAt: Date = .now, thumbnailURL: URL? = nil, templateTag: String = "Default") {
        self.id = id; self.title = title; self.durationSec = durationSec
        self.exportURL = exportURL; self.createdAt = createdAt
        self.thumbnailURL = thumbnailURL; self.templateTag = templateTag
    }
}
