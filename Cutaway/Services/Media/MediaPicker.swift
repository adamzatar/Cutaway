//
//  MediaPicker.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import Foundation
import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// SwiftUI-friendly PHPicker for a single *video* that returns a local file URL you own.
/// - Copies the picked video into your app's Documents/imports directory.
/// - Returns the new URL via `onPicked`.
struct MediaPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .videos
        // Prefer current representation (original), avoid transcoding at pick time
        config.preferredAssetRepresentationMode = .current

        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let itemProvider = results.first?.itemProvider else {
                picker.dismiss(animated: true) { self.parent.onCancel() }
                return
            }

            // Ask for a file URL; PHPicker can vend either movie or raw data.
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    DispatchQueue.main.async {
                        picker.dismiss(animated: true) {}
                    }
                    if let error { print("Picker loadFile error:", error.localizedDescription) }
                    guard let srcURL = url else { return self.parent.onCancel() }
                    self.copyToImportsAndReturn(srcURL: srcURL)
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.audiovisualContent.identifier) {
                // Fallback: load data and write it ourselves
                itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.audiovisualContent.identifier) { data, error in
                    DispatchQueue.main.async {
                        picker.dismiss(animated: true) {}
                    }
                    if let error { print("Picker loadData error:", error.localizedDescription) }
                    guard let data, !data.isEmpty else { return self.parent.onCancel() }
                    self.writeDataToImportsAndReturn(data: data)
                }
            } else {
                picker.dismiss(animated: true) { self.parent.onCancel() }
            }
        }

        // MARK: - File moves

        private func copyToImportsAndReturn(srcURL: URL) {
            do {
                let dest = try Self.makeImportsURL(withExtension: srcURL.pathExtension)
                // Ensure fresh destination
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: srcURL, to: dest)
                DispatchQueue.main.async { self.parent.onPicked(dest) }
            } catch {
                print("Copy to imports failed:", error)
                DispatchQueue.main.async { self.parent.onCancel() }
            }
        }

        private func writeDataToImportsAndReturn(data: Data) {
            do {
                let dest = try Self.makeImportsURL(withExtension: "mov")
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async { self.parent.onPicked(dest) }
            } catch {
                print("Write to imports failed:", error)
                DispatchQueue.main.async { self.parent.onCancel() }
            }
        }

        private static func makeImportsURL(withExtension ext: String) throws -> URL {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir = docs.appendingPathComponent("imports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("main-\(UUID().uuidString).\(ext)")
        }
    }
}

