//
//  PreviewCTA.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/19/25.
//
"""



"""
import Foundation
import SwiftUI


struct PreviewCTA: View {
    let enabled: Bool
    let onOpen: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(.white)
                    Text("Preview & Export")
                        .font(.headline)
                }

                Text("We’ll auto‑stitch main ↔ reactions. Fine‑tune rhythm & add bleeps next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onOpen) {
                    Label("Open Preview", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                // If you have GradientButtonStyle, you can swap this back in.
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.lavender)
                .disabled(!enabled)
                .opacity(enabled ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: enabled)
            }
        }
    }
}

// Local “glass card” so this file is standalone.
// (Matches the style of the Card used in HomeView.)
private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .padding(.horizontal, 18)
    }
}
