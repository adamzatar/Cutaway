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

/// Shows a lightweight preview (plays the main clip) and handles export UX (progress, share).
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel

    // Simple local preview player — this is *not* the final edit, just the main clip for context.
    @State private var player: AVPlayer?

    // Share sheet
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // PREVIEW PLAYER
            ZStack {
                if let p = player {
                    VideoPlayer(player: p)
                        .onAppear { p.play() }
                        .onDisappear { p.pause() }
                        .frame(maxHeight: 320)
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.1))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("Preview")
                                    .foregroundStyle(.secondary)
                            }
                        )
                        .frame(maxHeight: 320)
                }
            }

            // EXPORT CONTROLS
            Form {
                Section("Episode") {
                    HStack {
                        Label("Main", systemImage: "film")
                        Spacer()
                        Text(viewModel.mainClipURL.lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Reactions", systemImage: "person.line.dotted.person.fill")
                        Spacer()
                        Text("\(viewModel.reactions.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if viewModel.isExporting {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView(value: Double(viewModel.exportProgress), total: 1.0)
                                    .progressViewStyle(.linear)
                                Text("\(Int(viewModel.exportProgress * 100))%")
                                    .monospacedDigit()
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                viewModel.cancelExport()
                            } label: {
                                Label("Cancel Export", systemImage: "xmark.circle")
                            }
                        }
                    } else {
                        Button {
                            viewModel.exportEpisode()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up.on.square")
                                Text("Export Episode")
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if let err = viewModel.exportError {
                            Text(err).foregroundStyle(.red).font(.footnote)
                        }
                    }
                }

                if let url = viewModel.exportSuccessURL {
                    Section("Exported") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Saved file ready")
                            Spacer()
                            Button("Share") { showShareSheet = true }
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ActivityView(items: [url])
                        }

                        Button {
                            // Quick local playback of the final render
                            let p = AVPlayer(url: url)
                            self.player = p
                            p.play()
                        } label: {
                            Label("Play Final", systemImage: "play.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Set up a simple preview of the *main* clip for context (not the final edit)
            self.player = AVPlayer(url: viewModel.mainClipURL)
        }
    }
}

// MARK: - UIKit Share Sheet wrapper

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


// MARK: - Preview

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.mov")
    let store = LibraryStore()
    let vm = PreviewViewModel(mainClipURL: tmp, reactions: [], library: store)
    NavigationStack { PreviewView(viewModel: vm) }
        .environmentObject(store) // optional, nice to have
}
