//
//  SplashView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/19/25.
//


import SwiftUI
import CoreMotion

struct SplashView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .stroke
    @State private var logoTrim: CGFloat = 0
    @State private var logoFillOpacity: CGFloat = 0
    @State private var glowOpacity: CGFloat = 0.0
    @State private var titleOpacity: CGFloat = 0.0
    @State private var scale: CGFloat = 0.98
    @StateObject private var motion = ParallaxTiltManager()

    enum Phase { case stroke, fill, title, handoff }

    var onFinish: () -> Void

    var body: some View {
        ZStack {
            // BACKGROUND
            ZStack {
                if UIImage(named: "LaunchGradient") != nil {
                    Image("LaunchGradient")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    LinearGradient(colors: [.purple, .blue],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                }

                if scheme == .dark {
                    LinearGradient(colors: [.black.opacity(0.3), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }

                NoiseOverlay(opacity: scheme == .dark ? 0.08 : 0.06)
                    .ignoresSafeArea()
            }

            // CONTENT
            VStack(spacing: 18) {
                ZStack {
                    // 1) Stroke-style reveal (mask over logo)
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(.white)
                        .opacity(phase == .stroke ? 1 : 0)
                        .modifier(ParallaxTilt(amount: motion.amount))
                        .scaleEffect(scale)
                        .mask(
                            Rectangle()
                                .trim(from: 0, to: logoTrim)
                                .stroke(style: StrokeStyle(lineWidth: 300))
                                .foregroundStyle(.white)
                        )

                    // 2) Filled logo fade-in
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .opacity(logoFillOpacity)
                        .modifier(ParallaxTilt(amount: motion.amount))
                        .scaleEffect(scale)

                    // 3) Glow
                    Circle()
                        .fill(.white.opacity(0.25))
                        .blur(radius: 24)
                        .frame(width: 160, height: 160)
                        .opacity(glowOpacity)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }

                // Title
                Text("Cutaway")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.98))
                    .opacity(titleOpacity)
                    .modifier(ParallaxTilt(amount: motion.amount))
            }
            .padding(.bottom, 32)
        }
        .onAppear { runAnimation() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .handoff {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    onFinish()
                }
            }
        }
        .task {
            motion.enabled = !reduceMotion
            if reduceMotion {
                motion.amount = .zero
            }
        }
    }

    // MARK: Timeline

    private func runAnimation() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { scale = 1.0 }

        withAnimation(.easeInOut(duration: reduceMotion ? 0.45 : 0.9)) {
            logoTrim = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.35 : 0.8)) {
            phase = .fill
            withAnimation(.easeOut(duration: 0.45)) {
                logoFillOpacity = 1.0
                glowOpacity = 0.6
            }
            withAnimation(.easeInOut(duration: 0.6).delay(0.1)) {
                glowOpacity = 0.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.55 : 1.25)) {
            phase = .title
            withAnimation(.easeOut(duration: 0.35)) { titleOpacity = 1.0 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.95 : 1.85)) {
            withAnimation(.easeInOut(duration: 0.35)) { scale = 1.02 }
            phase = .handoff
        }
    }
}

// MARK: - Parallax Manager

private final class ParallaxTiltManager: ObservableObject {
    private let mgr = CMMotionManager()
    @Published var amount: CGSize = .zero
    var enabled: Bool = true
    var amountScale: CGFloat = 10

    init() {
        if mgr.isDeviceMotionAvailable {
            mgr.deviceMotionUpdateInterval = 1.0 / 60.0
            mgr.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, self.enabled, let m = motion else { return }
                let x = CGFloat(m.gravity.x) * self.amountScale
                let y = CGFloat(-m.gravity.y) * self.amountScale
                self.amount = CGSize(width: x, height: y)
            }
        }
    }
    deinit { mgr.stopDeviceMotionUpdates() }
}

private struct ParallaxTilt: ViewModifier {
    let amount: CGSize
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(amount.width) * 0.5), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(Double(amount.height) * 0.5), axis: (x: 1, y: 0, z: 0))
            .offset(x: amount.width * 0.15, y: amount.height * 0.15)
    }
}

// MARK: - Noise Overlay


private struct NoiseOverlay: View {
    let opacity: CGFloat
    var body: some View {
        Image("NoiseTexture") // <- Add a subtle grain PNG (256x256) in Assets
            .resizable(resizingMode: .tile)
            .ignoresSafeArea()
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    
}
