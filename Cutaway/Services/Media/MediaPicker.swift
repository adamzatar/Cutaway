//
//  MediaPicker.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for PHPicker that imports a *single* video and hands you a local file URL.
/// It copies the picked movie out of the temporary security-scoped location into your app's
/// temporary directory so you fully own the file (and can feed it to AVFoundation).
public struct MediaPicker: UIViewControllerRepresentable {
    /// Called when the user picked a video and we've copied it to an app-owned URL.
    public let onPicked: (URL) -> Void
    /// Called when user cancels or we fail to retrieve a video.
    public let onCancel: () -> Void

    public init(onPicked: @escaping (URL) -> Void,
                onCancel: @escaping () -> Void) {
        self.onPicked = onPicked
        self.onCancel = onCancel
    }

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos               // videos only
        config.selectionLimit = 1             // single selection
        config.preferredAssetRepresentationMode = .current // don't auto-transcode

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MediaPicker
        init(parent: MediaPicker) { self.parent = parent }

        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Always dismiss first; then deliver callbacks.
            defer { picker.dismiss(animated: true, completion: nil) }

            guard let result = results.first else {
                parent.onCancel()
                return
            }

            let provider = result.itemProvider
            // Use the UniformTypeIdentifiers movie type
            let movieUTI = UTType.movie.identifier

            if provider.hasItemConformingToTypeIdentifier(movieUTI) {
                provider.loadFileRepresentation(forTypeIdentifier: movieUTI) { [weak self] tempURL, error in
                    guard let self else { return }
                    // Jump to main for callbacks after we copy
                    if let error = error {
                        DispatchQueue.main.async { self.parent.onCancel() }
                        print("MediaPicker error: \(error.localizedDescription)")
                        return
                    }
                    guard let tempURL else {
                        DispatchQueue.main.async { self.parent.onCancel() }
                        return
                    }

                    // Copy to an app-owned temp location (so it persists beyond picker lifecycle)
                    let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("import-\(UUID().uuidString).\(ext)")

                    do {
                        // Remove if a previous file exists at dest (very unlikely)
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: tempURL, to: dest)
                        DispatchQueue.main.async { self.parent.onPicked(dest) }
                    } catch {
                        print("MediaPicker copy error: \(error)")
                        DispatchQueue.main.async { self.parent.onCancel() }
                    }
                }
            } else {
                // Fallback: ask for public.movie via data rep if needed (rare)
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: movieUTI) { [weak self] url, _, _ in
                    guard let self, let url else {
                        DispatchQueue.main.async { self?.parent.onCancel() }
                        return
                    }
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("import-\(UUID().uuidString).\(ext)")
                    do {
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: url, to: dest)
                        DispatchQueue.main.async { self.parent.onPicked(dest) }
                    } catch {
                        print("MediaPicker fallback copy error: \(error)")
                        DispatchQueue.main.async { self.parent.onCancel() }
                    }
                }
            }
        }
    }
}
