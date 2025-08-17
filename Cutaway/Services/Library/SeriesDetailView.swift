//
//  SeriesDetailView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/16/25.
//

import SwiftUI
import AVKit

struct SeriesDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let series: Series
    @State private var selectedEpisode: Episode?

    private var episodes: [Episode] {
        library.series.first(where: { $0.id == series.id })?.episodes ?? []
    }

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(episodes) { ep in
                    VStack(alignment: .leading, spacing: 6) {
                        EpisodeCard(episode: ep)
                            .onTapGesture { selectedEpisode = ep }
                            .contextMenu {
                                Button(role: .destructive) {
                                    library.removeEpisode(id: ep.id, in: series.id)
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    share(url: ep.exportURL)
                                } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            }
                        Text(ep.title).font(.subheadline).lineLimit(1)
                        Text(DateFormatter.short.string(from: ep.createdAt))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .navigationTitle("\(series.emoji) \(series.title)")
        .sheet(item: $selectedEpisode) { ep in
            PlayerSheet(url: ep.exportURL, title: ep.title)
        }
    }

    private func share(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.present(alert: av)
    }
}

// Card with thumbnail or placeholder
private struct EpisodeCard: View {
    let episode: Episode
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = episode.thumbnailURL,
               let img = image ?? UIImage(contentsOfFile: thumb.path) {
                Image(uiImage: img).resizable().scaledToFill()
                    .onAppear { image = img }
            } else {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.15))
                    Image(systemName: "play.rectangle.fill").font(.system(size: 32)).foregroundStyle(.secondary)
                }
            }
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            Text("\(Int(episode.durationSec))s")
                .font(.caption2).foregroundStyle(.white).padding(6)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// Simple player sheet
private struct PlayerSheet: View {
    let url: URL
    let title: String
    @State private var player = AVPlayer()

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play() }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
    @Environment(\.dismiss) private var dismiss
}

// Utilities
private extension DateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
private extension UIApplication {
    func present(alert: UIViewController) {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
    }
}
private extension UIWindowScene { var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } } }

#Preview {
    let seeded = LibraryStore.previewSeed()
    NavigationStack {
        SeriesDetailView(series: seeded.series)
    }
    .environmentObject(seeded.store)
}

#if DEBUG
extension LibraryStore {
    static func previewSeed() -> (store: LibraryStore, series: Series) {
        let store = LibraryStore()
        let sid = store.ensureSeries("Demo Show", emoji: "🎬")
        let eps = [
            Episode(title: "Ep 101", durationSec: 42, exportURL: URL(fileURLWithPath: "/tmp/fake1.mp4")),
            Episode(title: "Ep 102", durationSec: 55, exportURL: URL(fileURLWithPath: "/tmp/fake2.mp4")),
        ]
        for ep in eps {
            store.addEpisode(ep, to: sid, fallbackTitle: "Demo Show", emoji: "🎬")
        }
        // fetch the series we just created
        let series = store.series.first { $0.id == sid }!
        return (store, series)
    }
}
#endif
