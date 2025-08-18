//
//  HomeView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import SwiftUI
import AVFoundation
import UIKit

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var vm = HomeViewModel()

    // Navigation
    @State private var goPreview = false
    @AppStorage("shouldAutoOpenPickerOnce") private var shouldAutoOpenPickerOnce = false

    // UI state
    @State private var showLibrary = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // BRAND BACKGROUND (uses the three brand colors from Theme.swift via hex init there)
                LinearGradient(
                    colors: [
                        BrandColor.peach.opacity(0.9),
                        BrandColor.rose.opacity(0.9),
                        BrandColor.lavender.opacity(0.9)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Greeting / title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cutaway")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Multi‑perspective mini‑episodes")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)

                        // ===== MAIN CLIP CARD =====
                        Card {
                            if let url = vm.mainClipURL {
                                // Compact summary when selected
                                HStack(alignment: .center, spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(.white.opacity(0.08))
                                            .frame(width: 96, height: 56)
                                        VideoThumbView(url: url)
                                            .frame(width: 96, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(vm.mainFilename ?? url.lastPathComponent)
                                            .font(.headline)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)

                                        if let d = vm.mainDurationSec {
                                            Text(String(format: "%.1fs", d))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)

                                    Button {
                                        vm.showingPicker = true
                                    } label: {
                                        Label("Change", systemImage: "square.and.pencil")
                                            .labelStyle(.titleAndIcon)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                // Spacious empty state with a BIG primary CTA
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "film")
                                            .font(.system(size: 22, weight: .semibold))
                                        Text("Add your main clip")
                                            .font(.headline)
                                    }

                                    Text("Pick a video from Photos to be the foundation of your episode.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        vm.showingPicker = true
                                    } label: {
                                        Label("Pick from Photos", systemImage: "photo.on.rectangle")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(GradientButtonStyle()) // from Theme.swift
                                }
                            }
                        }

                        // ===== REACTIONS CARD =====
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "person.line.dotted.person.fill")
                                        .foregroundStyle(.white)
                                    Text("Reactions")
                                        .font(.headline)
                                }

                                if vm.reactions.isEmpty {
                                    Text("Record 1–3 front‑camera reactions.")
                                        .foregroundStyle(.secondary)
                                        .transition(.opacity)
                                } else {
                                    FlowRow(spacing: 8) {
                                        ForEach(vm.reactions) { r in
                                            Text(r.displayName.isEmpty ? "Guest" : r.displayName)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(.ultraThinMaterial)
                                                .clipShape(Capsule())
                                                .contextMenu {
                                                    Button("Rename") { renameReaction(r) }
                                                    Button(role: .destructive) {
                                                        vm.removeReaction(id: r.id)
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                }
                                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                        }
                                    }
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        vm.showingRecord = true
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    } label: {
                                        Label("Record Reaction", systemImage: "camera.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(BrandColor.lavender)

                                    if !vm.reactions.isEmpty {
                                        Button(role: .destructive) {
                                            vm.clearAll()
                                        } label: {
                                            Label("Clear", systemImage: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                        // ===== PREVIEW / CTA CARD =====
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundStyle(.white)
                                    Text("Preview & Export")
                                        .font(.headline)
                                }
                                Text("We’ll auto‑stitch main ↔ reactions. You can fine‑tune rhythm & add bleeps next.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    if vm.isReadyForPreview {
                                        goPreview = true
                                    } else {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                    }
                                } label: {
                                    Label("Open Preview", systemImage: "sparkles")
                                        .font(.headline)
                                }
                                .buttonStyle(GradientButtonStyle()) // from Theme.swift
                                .disabled(!vm.isReadyForPreview)
                            }
                            // Hidden NavigationLink that actually drives the push
                            .background(
                                NavigationLink(
                                    destination: {
                                        if let pvm = vm.makePreviewViewModel(library: library) {
                                            PreviewView(viewModel: pvm)
                                        } else {
                                            Text("Missing media").font(.headline)
                                        }
                                    },
                                    isActive: $goPreview,
                                    label: { EmptyView() }
                                )
                                .opacity(0)
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("") // large custom title
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showLibrary = true } label: {
                        Image(systemName: "sparkles.tv")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            // Sheets
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
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(library)
            }
            .navigationDestination(isPresented: $showLibrary) {
                LibraryView().environmentObject(library)
            }
            // Auto‑open picker when Intro’s “Start New Episode” triggers
            .onReceive(NotificationCenter.default.publisher(for: .CutawayOpenPicker)) { _ in
                vm.showingPicker = true
            }
        }
        .onAppear {
            // Smooth Intro → Home → Picker handoff
            if shouldAutoOpenPickerOnce {
                shouldAutoOpenPickerOnce = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    vm.showingPicker = true
                }
            }
        }
    }

    // MARK: - Private

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

// MARK: - Styled Components (simple card for consistency with theme)

private struct Card<Content: View>: View {
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

// Simple flow layout for reaction chips
private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing; self.content = content()
    }
    var body: some View {
        var width: CGFloat = 0, height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content
                    .alignmentGuide(.leading) { d in
                        if width + d.width > geo.size.width {
                            width = 0; height -= (d.height + spacing)
                        }
                        defer { width += d.width + spacing }
                        return width
                    }
                    .alignmentGuide(.top) { _ in height }
            }
        }
        .frame(height: 80)
    }
}

// Thumbnail from local file
private struct VideoThumbView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.06))
                    .overlay(ProgressView().tint(.white.opacity(0.8)))
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
        let cg = try gen.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        return UIImage(cgImage: cg)
    }
}

// Tiny UIKit presenter for rename
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
