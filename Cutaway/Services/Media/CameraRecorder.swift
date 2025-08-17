//
//  CameraRecorder.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import Foundation
import SwiftUI
import AVFoundation
import CoreMedia
import UIKit

/// Lightweight front‑camera + mic movie recorder suitable for SwiftUI.
/// - Permissions handled internally
/// - 720p for perf
/// - 30s cap (configurable)
/// - Writes .mov into a temp URL and calls `onFinished` or `onFailed`
final class CameraRecorder: NSObject, ObservableObject {

    // MARK: - Public observable state (updated on main)
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?

    /// Called when a recording finishes successfully with the file URL.
    var onFinished: ((URL) -> Void)?
    /// Called when a recording fails or is cancelled.
    var onFailed: ((Error) -> Void)?

    // MARK: - Private capture graph
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    /// All capture mutations happen here (off main).
    private let sessionQueue = DispatchQueue(label: "CameraRecorder.session")

    /// Max duration for a single reaction clip (default 30s).
    var maxSeconds: Double = 30 {
        didSet {
            let t = CMTime(seconds: max(1, maxSeconds), preferredTimescale: 600)
            movieOutput.maxRecordedDuration = t
        }
    }

    /// Preview layer to embed in SwiftUI (via `CameraPreviewView` below).
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        return l
    }()

    // MARK: - Lifecycle

    override init() {
        super.init()
        // sensible defaults
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSeconds, preferredTimescale: 600)
        movieOutput.movieFragmentInterval = .invalid // write single moov atom at end
    }

    deinit {
        session.stopRunning()
    }

    // MARK: - Permissions

    enum CameraPermissionError: LocalizedError {
        case cameraDenied, micDenied
        var errorDescription: String? {
            switch self {
            case .cameraDenied: return "Camera access is denied."
            case .micDenied:    return "Microphone access is denied."
            }
        }
    }

    /// Ask for camera + mic permission if needed (awaits prompts).
    private func ensurePermissions() async throws {
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

    // MARK: - Configure / Start / Stop

    /// Prepare the session graph: front camera + mic → movie file output.
    func configureSession() async throws {
        try await ensurePermissions()

        let uiOrientation: UIInterfaceOrientation = await MainActor.run {
            (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.interfaceOrientation) ?? .portrait
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: NSError(domain: "CameraRecorder", code: -1))
                    return
                }
                do {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }

                    self.session.sessionPreset = .hd1280x720

                    if let vi = self.videoInput { self.session.removeInput(vi) }
                    if let ai = self.audioInput { self.session.removeInput(ai) }
                    if self.session.outputs.contains(self.movieOutput) {
                        self.session.removeOutput(self.movieOutput)
                    }

                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                               for: .video,
                                                               position: .front) else {
                        throw NSError(domain: "CameraRecorder",
                                      code: -2,
                                      userInfo: [NSLocalizedDescriptionKey: "Front camera unavailable"])
                    }

                    if (try? device.lockForConfiguration()) != nil {
                        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                        device.unlockForConfiguration()
                    }

                    let vInput = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(vInput) { self.session.addInput(vInput); self.videoInput = vInput }

                    if let mic = AVCaptureDevice.default(for: .audio) {
                        let aInput = try AVCaptureDeviceInput(device: mic)
                        if self.session.canAddInput(aInput) { self.session.addInput(aInput); self.audioInput = aInput }
                    }

                    if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }

                    if let conn = self.movieOutput.connection(with: .video) {
                        conn.isVideoMirrored = true
                        self.applyOrientation(uiOrientation, to: conn)
                        if conn.isVideoStabilizationSupported {
                            conn.preferredVideoStabilizationMode = .auto
                        }
                    }

                    // ✅ Return Void explicitly
                    cont.resume(returning: ())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Start camera capture (preview).
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = true }
        }
    }

    /// Stop camera capture (preview).
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    // MARK: - Recording

    /// Begin recording to a temp .mov file. Use `stopRecording()` to end early, or it auto‑stops at `maxSeconds`.
    func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction-\(UUID().uuidString).mov")

        // Refresh orientation from main, then start on session queue
        Task { @MainActor in
            let uiOrientation = (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.interfaceOrientation) ?? .portrait

            sessionQueue.async { [weak self] in
                guard let self else { return }
                if let conn = self.movieOutput.connection(with: .video) {
                    self.applyOrientation(uiOrientation, to: conn)
                    conn.isVideoMirrored = true
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                DispatchQueue.main.async { self.isRecording = true }
            }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: - Orientation helpers

    /// Apply UIInterfaceOrientation to the capture connection using the best API per iOS version.
    private func applyOrientation(_ io: UIInterfaceOrientation, to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            // Use rotation angles (degrees)
            switch io {
            case .landscapeLeft:  connection.videoRotationAngle = 90
            case .landscapeRight: connection.videoRotationAngle = 270
            case .portraitUpsideDown: connection.videoRotationAngle = 180
            default: connection.videoRotationAngle = 0
            }
        } else {
            // Legacy orientation API (deprecated in iOS 17, fine on 16)
            if connection.isVideoOrientationSupported {
                switch io {
                case .landscapeLeft:  connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                default: connection.videoOrientation = .portrait
                }
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        // No‑op (UI already updated on start)
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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

// MARK: - SwiftUI preview host for the camera layer

/// A SwiftUI view that hosts `AVCaptureVideoPreviewLayer` (fills its space).
struct CameraPreviewView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHost {
        let v = PreviewHost()
        v.backgroundColor = .black
        layer.frame = v.bounds
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ uiView: PreviewHost, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }

    final class PreviewHost: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
