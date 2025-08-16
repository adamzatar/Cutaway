//
//  Series.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

import Foundation

/// A "show" that groups multiple Episodes, like seasons in a Netflix library.
public struct Series: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var emoji: String
    public var episodes: [Episode]   // newest first is fine

    public init(id: UUID = UUID(),
                title: String,
                emoji: String,
                episodes: [Episode] = []) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.episodes = episodes
    }
}
