//
//  Theme.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/17/25.
//

// Design/Theme.swift
import SwiftUI

// MARK: - Brand Palette (Sunset Calm + complementary accents)
enum BrandColor {
    // Core gradient stops (your picks)
    static let peach    = Color(hex: 0xF9D5A0)  // soft, friendly
    static let rose     = Color(hex: 0xE48E8E)  // warm emotion
    static let lavender = Color(hex: 0xC4A7FF)  // soothing, modern

    // Companions (muted, non-neon; chosen to work in light/dark)
    static let deepNavy   = Color(hex: 0x111322)
    static let ink        = Color(hex: 0x0B0C12)
    static let mist       = Color(hex: 0xF6F6F9)
    static let graphite   = Color(hex: 0x2A2B31)
    static let silverText = Color(hex: 0x9AA0A6)
    static let mint       = Color(hex: 0x49D3B4) // subtle success
    static let coral      = Color(hex: 0xFF7A70) // subtle alert/accent
}

// MARK: - Semantic colors (auto-choose per scheme)
enum AppColor {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? BrandColor.ink : .white
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? BrandColor.graphite : BrandColor.mist
    }
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(hex: 0x202227)
    }
    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? BrandColor.silverText : Color(hex: 0x6B6F76)
    }
}

// MARK: - Gradients
enum BrandGradient {
    /// Main brand sweep (Sunset Calm)
    static func primary(angle: Angle = .degrees(135)) -> LinearGradient {
        LinearGradient(
            colors: [BrandColor.peach, BrandColor.rose, BrandColor.lavender],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle background glow for dark mode
    static func halo() -> RadialGradient {
        RadialGradient(
            colors: [BrandColor.lavender.opacity(0.35), .clear],
            center: .topLeading, startRadius: 40, endRadius: 420
        )
    }

    /// Soft glass highlight
    static func glass() -> LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.28), .white.opacity(0.06)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Reusable styles
struct GradientButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(BrandGradient.primary())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.35 : 0.18), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
