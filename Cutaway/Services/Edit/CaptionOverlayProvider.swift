//
//  CaptionOverlayProvider.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import UIKit
import AVFoundation
import UIKit
import AVFoundation

// MARK: - Overlay abstraction

/// Abstraction so the composer is overlay‑agnostic.
/// Return a root CALayer that animates overlays at the correct times for a given render size.
public protocol OverlayRendering {
    func makeOverlayLayer(for overlays: [Overlay], renderSize: CGSize) -> CALayer?
}

// MARK: - Concrete provider

/// Builds Core Animation overlays (lower‑thirds, etc.).
/// Using `struct` + `public init()` so you can construct it (`CaptionOverlayProvider()`).
public struct CaptionOverlayProvider: OverlayRendering {

    public init() {}

    // Protocol entry point (instance)
    public func makeOverlayLayer(for overlays: [Overlay], renderSize: CGSize) -> CALayer? {
        return Self.makeLayer(for: overlays, renderSize: renderSize)
    }

    // Static convenience (useful in tests or call sites that prefer static)
    public static func makeLayer(for overlays: [Overlay],
                                 renderSize: CGSize) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: renderSize)
        root.masksToBounds = true
        root.isGeometryFlipped = true  // match video coordinate space (origin top‑left)

        for ov in overlays {
            switch ov.payload {
            case .lowerThird(let text, let emoji):
                let layer = makeLowerThird(text: text, emoji: emoji, renderSize: renderSize)
                // Animate opacity during [start, end]
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.beginTime = ov.range.start.seconds
                fade.duration = max(0.001, ov.range.duration.seconds)
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                layer.add(fade, forKey: "appear")
                root.addSublayer(layer)
            }
        }
        return root
    }

    // MARK: - Lower Third (pill) factory

    /// Creates a pill-style lower‑third layer with emoji + text.
    /// Position: bottom-left, safe insets; auto-sizes by text length, caps at 70% width.
    public static func makeLowerThird(text: String,
                                      emoji: String,
                                      renderSize: CGSize,
                                      bottomInset: CGFloat = 88,
                                      sideInset: CGFloat = 24) -> CALayer {

        let message = messageString(emoji: emoji, text: text)

        // Sizing constants
        let font = UIFont.boldSystemFont(ofSize: 20)
        let maxWidth = renderSize.width * 0.7
        let minWidth: CGFloat = 160
        let height: CGFloat = 44
        let horizontalPadding: CGFloat = 18

        // Rough width estimation using NSString sizing (fast + good enough)
        let estimated = (message as NSString).size(withAttributes: [.font: font]).width
        let width = min(maxWidth, max(minWidth, estimated + horizontalPadding * 2))

        // Container "pill"
        let container = CALayer()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.55).cgColor
        container.cornerRadius = height / 2
        container.masksToBounds = true

        // Position near bottom-left with safe-ish inset
        let origin = CGPoint(x: sideInset, y: renderSize.height - bottomInset)
        container.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))

        // Text layer (CATextLayer renders in offline video pipeline)
        let textLayer = CATextLayer()
        textLayer.string = message
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.truncationMode = .end
        textLayer.frame = container.bounds.insetBy(dx: horizontalPadding, dy: 8)

        container.addSublayer(textLayer)
        return container
    }

    /// Compose the display string, trimming & sanitizing for overlays.
    private static func messageString(emoji: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "Guest" : trimmed
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? safe : "\(e) \(safe)"
    }
}
