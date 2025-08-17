//
//  IntroView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

import SwiftUI

struct IntroView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var hasSeenIntro: Bool
    let startNewEpisode: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // subtle gradient bg
                LinearGradient(
                    colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer(minLength: 24)

                    LogoWordmark()
                        .padding(.top, 8)

                    Text("Multi‑perspective mini episodes.\nRecord reactions. Auto‑stitch. Share.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
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

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            hasSeenIntro = true
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

                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("Open Library", systemImage: "sparkles.tv")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 20)

                    Button {
                        hasSeenIntro = true
                    } label: {
                        Text("Skip for now")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 16)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

private struct FeatureListRow: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 30)
                .font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct LogoWordmark: View {
    @State private var wiggle = false
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 40, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .rotationEffect(.degrees(wiggle ? -5 : 5))
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: wiggle)
                Text("Cutaway")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }
            .onAppear { wiggle = true }
        }
    }
}

#Preview {
    let store = LibraryStore()
    return IntroView(hasSeenIntro: .constant(false), startNewEpisode: {})
        .environmentObject(store)
}
