//
//  Episode.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//


import Foundation

public struct Episode: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var durationSec: Double
    public var exportURL: URL                // final mp4 stored in app-owned folder
    public var createdAt: Date
    public var thumbnailURL: URL?            // generated frame (optional)
    public var templateTag: String           // "Trip", "Roast", "Game", etc.

    public init(id: UUID = UUID(),
                title: String,
                durationSec: Double,
                exportURL: URL,
                createdAt: Date = .now,
                thumbnailURL: URL? = nil,
                templateTag: String = "Default") {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.exportURL = exportURL
        self.createdAt = createdAt
        self.thumbnailURL = thumbnailURL
        self.templateTag = templateTag
    }
}
