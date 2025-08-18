//
//  CameraRecorder.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import Foundation
@preconcurrency import AVFoundation   // quiets Sendable warnings from AVF
import CoreMedia
import UIKit
import SwiftUI

/// Front‑camera + mic recorder for reaction clips.
/// - iOS 16+
/// - 720p preset (perf)
/// - 30s default cap
/// - Writes .mov to a temp URL
@MainActor
public final class CameraRecorder: NSObject, ObservableObject {

    // MARK: UI State (main-actor)
    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var lastError: String?

    /// Callback when a recording finishes successfully.
    public var onFinished: ((URL) -> Void)?
    /// Callback when a recording fails.
    public var onFailed: ((Error) -> Void)?

    // MARK: Capture Graph (lives on a private queue)
    // Marked nonisolated(unsafe) so @Sendable closures on `sessionQueue` can access.
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?

    /// Heavy work queue (not main actor).
    private let sessionQueue = DispatchQueue(label: "CameraRecorder.session")

    /// SwiftUI can embed this layer via `CameraPreviewView`.
    public let previewLayer: AVCaptureVideoPreviewLayer

    /// Hard cap per clip (seconds). Default 30.
    public var maxSeconds: Double = 30 {
        didSet {
            let t = CMTime(seconds: max(1, maxSeconds), preferredTimescale: 600)
            movieOutput.maxRecordedDuration = t
        }
    }

    // MARK: Lifecycle

    public override init() {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspectFill

        movieOutput.movieFragmentInterval = .invalid  // single moov atom at end
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSeconds, preferredTimescale: 600)
    }

    deinit {
        // Stop safely off-main (we’re not touching @Published here).
        sessionQueue.async { [session] in session.stopRunning() }
    }

    // MARK: Permissions

    public enum CameraPermissionError: LocalizedError {
        case cameraDenied, micDenied
        public var errorDescription: String? {
            switch self {
            case .cameraDenied: return "Camera access is denied."
            case .micDenied:    return "Microphone access is denied."
            }
        }
    }

    public func requestPermissions() async throws {
        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
            if !ok { throw CameraPermissionError.cameraDenied }
        default:
            throw CameraPermissionError.cameraDenied
        }
        // Mic
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
            if !ok { throw CameraPermissionError.micDenied }
        default:
            throw CameraPermissionError.micDenied
        }
    }

    // MARK: Configure / Start / Stop

    /// Build the session graph (front camera + mic → movie output).
    public func configureSession() async throws {
        try await requestPermissions()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }

                    session.sessionPreset = .hd1280x720

                    // Clean any prior config
                    if let vi = videoInput { session.removeInput(vi) }
                    if let ai = audioInput { session.removeInput(ai) }
                    if session.outputs.contains(movieOutput) {
                        session.removeOutput(movieOutput)
                    }

                    // Front wide camera
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    else {
                        throw NSError(domain: "CameraRecorder", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Front camera unavailable"])
                    }

                    // Tuning
                    try? camera.lockForConfiguration()
                    if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                    if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                    camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    camera.unlockForConfiguration()

                    let vIn = try AVCaptureDeviceInput(device: camera)
                    if session.canAddInput(vIn) { session.addInput(vIn); videoInput = vIn }

                    if let mic = AVCaptureDevice.default(for: .audio) {
                        let aIn = try AVCaptureDeviceInput(device: mic)
                        if session.canAddInput(aIn) { session.addInput(aIn); audioInput = aIn }
                    }

                    if session.canAddOutput(movieOutput) {
                        session.addOutput(movieOutput)
                    }

                    // Update UI state on main
                    Task { @MainActor in
                        self.isSessionRunning = self.session.isRunning
                    }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func startSession() {
        sessionQueue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in self.isSessionRunning = true }
        }
    }

    public func stopSession() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in self.isSessionRunning = false }
        }
    }

    // MARK: Recording

    public func startRecording() {
        guard !isRecording else { return }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction-\(UUID().uuidString).mov")

        // Compute rotation angle on main (UIKit), then apply on session queue.
        let angle = currentVideoRotationAngleMainActor()

        sessionQueue.async { [self] in
            applyConnectionOrientationOnQueue(angle: angle)
            movieOutput.startRecording(to: dest, recordingDelegate: self)
            Task { @MainActor in self.isRecording = true }
        }
    }

    public func stopRecording() {
        sessionQueue.async { [self] in
            guard movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    // MARK: Orientation helpers

    /// Read UI orientation on the main actor and map to degrees.
    private func currentVideoRotationAngleMainActor() -> CGFloat {
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:      return 90
        case .landscapeRight:     return 270
        case .portraitUpsideDown: return 180
        default:                  return 0
        }
    }

    /// MUST be called from `sessionQueue`.
    nonisolated(unsafe) private func applyConnectionOrientationOnQueue(angle: CGFloat) {
        guard let conn = movieOutput.connection(with: .video) else { return }

        if #available(iOS 17.0, *) {
            conn.videoRotationAngle = angle
        } else {
            // iOS 16 fallback
            switch angle {
            case 90:  conn.videoOrientation = .landscapeLeft
            case 270: conn.videoOrientation = .landscapeRight
            case 180: conn.videoOrientation = .portraitUpsideDown
            default:  conn.videoOrientation = .portrait
            }
        }
        conn.isVideoMirrored = true
        if conn.isVideoStabilizationSupported {
            conn.preferredVideoStabilizationMode = .auto
        }
    }
}

// MARK: - Delegate (nonisolated in Swift 6)

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {

    public nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                       didStartRecordingTo fileURL: URL,
                                       from connections: [AVCaptureConnection]) {
        // optional log
    }

    public nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                       didFinishRecordingTo outputFileURL: URL,
                                       from connections: [AVCaptureConnection],
                                       error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            if let error {
                self.lastError = error.localizedDescription
                self.onFailed?(error)
            } else {
                self.onFinished?(outputFileURL)
            }
        }
    }
}

// MARK: - SwiftUI Preview Host

public struct CameraPreviewView: UIViewRepresentable {
    private let layer: AVCaptureVideoPreviewLayer
    public init(layer: AVCaptureVideoPreviewLayer) { self.layer = layer }

    public func makeUIView(context: Context) -> UIView {
        let v = PreviewHost()
        v.backgroundColor = .black
        layer.frame = v.bounds
        v.layer.addSublayer(layer)
        return v
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }

    private final class PreviewHost: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
