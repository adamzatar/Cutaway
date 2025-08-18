//
//  IntroView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

//  IntroView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

import SwiftUI

struct IntroView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var library: LibraryStore

    /// Controlled by App (@AppStorage("hasSeenIntro"))
    @Binding var hasSeenIntro: Bool

    /// Closure provided by the App to signal "user wants to start now"
    let startNewEpisode: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: brand gradient with subtle halo in dark mode
                AppColor.background(scheme).ignoresSafeArea()
                BrandGradient.primary().opacity(scheme == .dark ? 0.18 : 0.28)
                    .ignoresSafeArea()
                if scheme == .dark {
                    BrandGradient.halo().ignoresSafeArea()
                }

                VStack(spacing: 22) {
                    Spacer(minLength: 24)

                    LogoLockup()
                        .padding(.top, 8)

                    Text("Multi‑perspective mini‑episodes.\nRecord reactions. Auto‑stitch. Share fast.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.secondaryText(scheme))
                        .padding(.horizontal, 24)

                    FeatureListRow(icon: "rectangle.on.rectangle.angled",
                                   title: "Import Main Clip",
                                   detail: "Pick from Photos")
                    FeatureListRow(icon: "face.smiling",
                                   title: "Record Reactions",
                                   detail: "Front camera + mic")
                    FeatureListRow(icon: "wand.and.stars",
                                   title: "Auto‑Stitch",
                                   detail: "Captions, music bed, bleeps")

                    Spacer(minLength: 8)

                    VStack(spacing: 12) {
                        // START NEW EPISODE
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            // 1) Dismiss intro
                            hasSeenIntro = true
                            // 2) Ask Home to auto-open the picker once (smooth delay handled in Home)
                            UserDefaults.standard.set(true, forKey: "shouldAutoOpenPickerOnce")
                            // 3) Notify App/Home (if you also listen to this)
                            startNewEpisode()
                        } label: {
                            Label("Start New Episode", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // OPEN LIBRARY
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("Open Library", systemImage: "sparkles.tv")
                                .font(.subheadline)
                                .foregroundStyle(AppColor.primaryText(scheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(AppColor.surface(scheme))
                                        .overlay(BrandGradient.glass().clipShape(RoundedRectangle(cornerRadius: 16)))
                                )
                        }
                    }
                    .padding(.horizontal, 20)

                    // SKIP → just dismiss intro (no picker)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        hasSeenIntro = true
                    } label: {
                        Text("Skip for now")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.bottom, 8)
            }
            .navigationBarHidden(true)
        }
    }
}

private struct FeatureListRow: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColor.surface(scheme).opacity(0.8))
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColor.primaryText(scheme))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.primaryText(scheme))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText(scheme))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct LogoLockup: View {
    @Environment(\.colorScheme) private var scheme
    @State private var wiggle = false

    var body: some View {
        VStack(spacing: 12) {
            // Abstract split-frames mark (brand)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(scheme == .dark ? 0.9 : 1.0))
                    .frame(width: 64, height: 48)
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(BrandColor.rose.opacity(0.9))
                    }

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(scheme == .dark ? 0.9 : 1.0))
                    .frame(width: 48, height: 48)
                    .overlay(alignment: .center) {
                        // Abstract "reaction" face hint
                        HStack(spacing: 3) {
                            Circle().fill(AppColor.primaryText(scheme)).frame(width: 4, height: 4)
                            Circle().fill(AppColor.primaryText(scheme)).frame(width: 4, height: 4)
                        }
                        .offset(y: -3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColor.primaryText(scheme))
                            .frame(width: 12, height: 2)
                            .offset(y: 6)
                    }
                    .rotationEffect(.degrees(wiggle ? -3 : 3))
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: wiggle)
            }

            Text("Cutaway")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.primaryText(scheme))
        }
        .onAppear { wiggle = true }
    }
}

#Preview {
    let store = LibraryStore()
    IntroView(hasSeenIntro: .constant(false), startNewEpisode: {})
        .environmentObject(store)
        .preferredColorScheme(.dark)
}
