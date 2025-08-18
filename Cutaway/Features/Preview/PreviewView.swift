//
//  PreviewView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import SwiftUI
import AVKit
import AVFoundation
import Combine

struct PreviewView: View {
    @StateObject private var viewModel: PreviewViewModel

    init(viewModel: PreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @Environment(\.colorScheme) private var scheme

    // Stitched preview player (TimelinePreviewBuilder output)
    @State private var player = AVPlayer()
    @State private var ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // BRAND BACKGROUND
            AppColor.background(scheme).ignoresSafeArea()
            BrandGradient.primary().opacity(scheme == .dark ? 0.18 : 0.28)
                .ignoresSafeArea()
            if scheme == .dark {
                BrandGradient.halo().ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 16) {

                    // HEADER PLAYER
                    VStack(alignment: .leading, spacing: 8) {
                        VideoPlayer(player: player)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .onAppear {
                                if viewModel.previewItem == nil {
                                    viewModel.rebuildPreview()
                                } else {
                                    player.replaceCurrentItem(with: viewModel.previewItem)
                                    player.play()
                                }
                            }
                            .onReceive(ticker) { _ in
                                let newItem = viewModel.previewItem
                                if player.currentItem !== newItem {
                                    player.replaceCurrentItem(with: newItem)
                                    if newItem != nil { player.play() }
                                }
                            }

                        Text("Live Preview")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .foregroundStyle(AppColor.primaryText(scheme))
                    }
                    .padding(.horizontal, 16)

                    // RHYTHM CARD
                    ThemedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "metronome.fill")
                                    .foregroundStyle(BrandColor.lavender)
                                Text("Alternating Rhythm")
                                    .font(.headline)
                            }

                            HStack {
                                Text("Main: \(Int(viewModel.mainChunkSec))s")
                                Slider(value: $viewModel.mainChunkSec, in: 3...12, step: 1)
                            }
                            HStack {
                                Text("Reaction: \(Int(viewModel.reactionChunkSec))s")
                                Slider(value: $viewModel.reactionChunkSec, in: 3...10, step: 1)
                            }
                            Text("Plays main → reaction → main → reaction, until time runs out.")
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText(scheme))
                        }
                    }
                    .onChange(of: viewModel.mainChunkSec) { _, _ in viewModel.rebuildPreview() }
                    .onChange(of: viewModel.reactionChunkSec) { _, _ in viewModel.rebuildPreview() }

                    // BLEEPS CARD
                    ThemedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "speaker.slash.fill")
                                    .foregroundStyle(BrandColor.coral)
                                Text("Bleeps")
                                    .font(.headline)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    let secs = player.currentTime().seconds
                                    viewModel.addBleep(at: secs.isFinite ? secs : 0)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label("Add at Playhead", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    player.seek(to: .zero)
                                } label: {
                                    Image(systemName: "gobackward")
                                }
                                .buttonStyle(.bordered)
                                .help("Jump to start")
                            }

                            if viewModel.bleepMarksSec.isEmpty {
                                Text("No bleeps yet. Add one at the current playhead time.")
                                    .foregroundStyle(AppColor.secondaryText(scheme))
                            } else {
                                ForEach(Array(viewModel.bleepMarksSec.enumerated()), id: \.offset) { idx, s in
                                    HStack {
                                        Text(String(format: "Bleep at %.2fs", s))
                                        Spacer()
                                        Button(role: .destructive) {
                                            viewModel.removeBleep(at: IndexSet(integer: idx))
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    // REACTIONS CARD
                    ThemedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "person.line.dotted.person.fill")
                                    .foregroundStyle(BrandColor.mint)
                                Text("Reactions Included")
                                    .font(.headline)
                            }

                            if viewModel.reactions.isEmpty {
                                Text("No reactions. Go back and record at least one.")
                                    .foregroundStyle(AppColor.secondaryText(scheme))
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(viewModel.reactions) { r in
                                            Text(r.displayName.isEmpty ? "Guest" : r.displayName)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(.ultraThinMaterial)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    // EXPORT CARD
                    VStack(spacing: 12) {
                        if viewModel.isExporting {
                            ProgressView(value: Double(viewModel.exportProgress))
                                .progressViewStyle(.linear)
                                .tint(BrandColor.lavender)

                            Button("Cancel Export") {
                                viewModel.cancelExport()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.exportEpisode()
                            } label: {
                                Label("Export Episode", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                            }
                            .buttonStyle(GradientButtonStyle())
                            .disabled(viewModel.reactions.isEmpty)
                        }

                        if let err = viewModel.exportError {
                            Text("Export failed: \(err)")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        if let url = viewModel.exportSuccessURL {
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                Text("Exported to Photos & Library")
                                Spacer()
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Themed Card

private struct ThemedCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surface(scheme))
                .overlay(BrandGradient.glass().clipShape(RoundedRectangle(cornerRadius: 16)))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.mov")
    let store = LibraryStore()
    let vm = PreviewViewModel(mainClipURL: tmp, reactions: [], library: store)
    return NavigationStack { PreviewView(viewModel: vm) }
        .environmentObject(store)
        .preferredColorScheme(.dark)
}
