//
//  HomeView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import SwiftUI
import AVFoundation

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var vm = HomeViewModel()
    @State private var goPreview = false

    var body: some View {
        NavigationStack {
            List {
                // MAIN CLIP
                Section {
                    if let url = vm.mainClipURL {
                        HStack(spacing: 12) {
                            VideoThumbView(url: url)
                                .frame(width: 84, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vm.mainFilename ?? url.lastPathComponent)
                                    .lineLimit(1)
                                if let d = vm.mainDurationSec {
                                    Text(String(format: "%.1fs", d))
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                            }
                            Spacer()
                            Button("Change") { vm.showingPicker = true }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No main clip selected")
                                .foregroundStyle(.secondary)
                            Button {
                                vm.showingPicker = true
                            } label: {
                                Label("Pick Main Video", systemImage: "photo.on.rectangle").foregroundColor(.white)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } header: {
                    Label("Main Clip", systemImage: "film")
                }

                // REACTIONS
                Section {
                    if vm.reactions.isEmpty {
                        Text("Record 1–3 reaction clips with the front camera.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(vm.reactions) { r in
                        HStack {
                            Text(r.displayName.isEmpty ? "Guest" : r.displayName)
                            Spacer()
                            Text(r.url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contextMenu {
                            Button("Rename") { renameReaction(r) }
                            Button(role: .destructive) { vm.removeReaction(id: r.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        vm.showingRecord = true
                    } label: {
                        Label("Record Reaction", systemImage: "camera.fill")
                    }
                } header: {
                    Label("Reactions", systemImage: "person.line.dotted.person.fill")
                }

                // CTA
                Section {
                    Button {
                        goPreview = true
                    } label: {
                        Label("Preview Episode", systemImage: "play.rectangle.fill")
                            .font(.headline)
                    }
                    .disabled(!vm.isReadyForPreview)
                }
            }
            .navigationTitle("Cutaway")
            .sheet(isPresented: $vm.showingPicker) {
                MediaPicker(
                    onPicked: { vm.setMainClip(url: $0) },
                    onCancel: { }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $vm.showingRecord) {
                ReactionRecordView { url in
                    vm.addReaction(url: url, displayName: "Me")
                }
            }
            .navigationDestination(isPresented: $goPreview) {
                if let pvm = vm.makePreviewViewModel(library: library) {
                    PreviewView(viewModel: pvm)
                } else {
                    Text("Missing main clip or reactions.")
                }
            }
        }
    }

    // Quick inline rename prompt
    private func renameReaction(_ r: ReactionClip) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = r.displayName; tf.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let name = alert.textFields?.first?.text ?? ""
            vm.renameReaction(id: r.id, to: name)
        }))
        UIApplication.shared.present(alert: alert)
    }
}

// MARK: - Helpers

/// Tiny UIKit presenter for rename
private extension UIApplication {
    func present(alert: UIAlertController) {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

/// Simple local video thumbnail
struct VideoThumbView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(.gray.opacity(0.2))
                    .overlay(ProgressView().tint(.secondary))
            }
        }
        .task {
            image = try? await generateThumb(url: url, at: 1.0)
        }
        .clipped()
    }

    private func generateThumb(url: URL, at seconds: Double) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 360)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let cg = try gen.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cg)
    }
}


#Preview {
    HomeView()
        .environmentObject(LibraryStore())
}
