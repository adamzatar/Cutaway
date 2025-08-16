//
//  Project.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation

/// A saved project on device. You can expand later with thumbnails, dates, etc.
public struct Project: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var mainURL: URL
    public var reactions: [ReactionClip]

    public init(id: UUID = UUID(), title: String, mainURL: URL, reactions: [ReactionClip]) {
        self.id = id
        self.title = title
        self.mainURL = mainURL
        self.reactions = reactions
    }
}

public struct ReactionClip: Identifiable, Codable {
    public let id: UUID
    public var url: URL
    public var displayName: String

    public init(id: UUID = UUID(), url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
    }
}
