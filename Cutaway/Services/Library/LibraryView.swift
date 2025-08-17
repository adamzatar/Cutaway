//
//  LibraryView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var newSeriesTitle: String = ""
    @State private var newSeriesEmoji: String = "📺"

    var body: some View {
        NavigationStack {
            List {
                if library.series.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("No series yet")
                                .font(.headline)
                            Text("Export an episode from Preview to see it here, or create an empty series to start organizing.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }

                ForEach(library.series) { s in
                    NavigationLink {
                        SeriesDetailView(series: s)
                    } label: {
                        HStack(spacing: 12) {
                            Text(s.emoji).font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).font(.headline)
                                Text("\(s.episodes.count) episode\(s.episodes.count == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            Spacer()
                            if let thumb = s.episodes.first?.thumbnailURL {
                                EpisodeThumb(url: thumb)
                                    .frame(width: 84, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            library.removeSeries(id: s.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            presentNewSeriesPrompt()
                        } label: { Label("New Series", systemImage: "plus") }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }
        }
    }

    private func presentNewSeriesPrompt() {
        let alert = UIAlertController(title: "New Series", message: "Name your show", preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "Title (e.g., Summer Trip)"; tf.autocapitalizationType = .words }
        alert.addTextField { tf in tf.placeholder = "Emoji (e.g., 🏖)"; tf.text = "📺" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default, handler: { _ in
            let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let emoji = alert.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "📺"
            guard !title.isEmpty else { return }
            _ = library.ensureSeries(title, emoji: emoji.isEmpty ? "📺" : emoji)
        }))
        UIApplication.shared.present(alert: alert)
    }
}

// Small file-thumb view (local file URLs)
private struct EpisodeThumb: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.gray.opacity(0.15))
                    .overlay(ProgressView().tint(.secondary))
            }
        }
        .task {
            if image == nil {
                image = UIImage(contentsOfFile: url.path)
            }
        }
        .clipped()
    }
}

// UIKit alert presenter
private extension UIApplication {
    func present(alert: UIAlertController) {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
    }
}
private extension UIWindowScene { var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } } }

#Preview {
    LibraryView().environmentObject(LibraryStore())
}
