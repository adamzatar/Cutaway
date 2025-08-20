//
//  Template.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/19/25.
//



import Foundation

public struct Template: Decodable {
    public let name: String
    public let layout: LayoutRule
    public let sfx: [SFXRule]

    public struct LayoutRule: Decodable {
        public let mode: EpisodePlan.LayoutMode     // now decodes thanks to Codable
        public let splitEveryNthCut: Int?
    }

    public struct SFXRule: Decodable {
        public enum Trigger: String, Decodable { case onCut, onBeat, onLaugh, onBleep }
        public let trigger: Trigger
        public let assetID: String
        public let cooldownSec: Double?
        public let gainDB: Float?
    }
}
