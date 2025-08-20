//
//  SFX.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/19/25.
//

import Foundation

public struct SFXAsset: Identifiable, Hashable {
    public let id: String           // "whoosh1"
    public let name: String
    public let fileURL: URL
    public let defaultGainDB: Float // -6 ... 0
    public let category: Category
    public enum Category: String { case whoosh, pop, rimshot, impact, ui, ambience }
}

public struct SFXEvent: Identifiable, Hashable {
    public let id = UUID()
    public var atSec: Double
    public var assetID: String
    public var gainDB: Float?       // override
    public var duckAroundSec: Double = 0.0 // optional extra duck
}
