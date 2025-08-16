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

/// Lightweight front‑camera + mic recorder for reaction clips.
/// - 720p preset
/// - 30s cap (configurable)
/// - Writes .mov to a temp URL you own
/// - Provides a preview layer usable in SwiftUI
public final class CameraRecorder: NSObject, ObservableObject {

    // MARK: - Published UI state (updated on main)
    @Published public private(set) var isSessionRunning: Bool = false
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var lastError: String?

    /// Called when a recording finishes successfully with the file URL.
    public var onFinished: ((URL) -> Void)?
    /// Called when a recording fails or is cancelled.
    public var onFailed: ((Error) -> Void)?

    // MARK: - Capture graph
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    /// A dedicated serial queue for all AVCaptureSession work.
    private let sessionQueue = DispatchQueue(label: "CameraRecorder.session")

    /// Max duration for a single reaction clip (default 30s).
    public var maxSeconds: Double = 30 {
        didSet {
            let t = CMTime(seconds: max(1, maxSeconds), preferredTimescale: 600)
            movieOutput.maxRecordedDuration = t
        }
    }

    /// Live preview layer for SwiftUI/UIView hosting.
    public lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        return l
    }()

    // MARK: - Lifecycle

    public override init() {
        super.init()
        // Delegate callbacks delivered on sessionQueue
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSeconds, preferredTimescale: 600)
        movieOutput.movieFragmentInterval = .invalid // write single moov atom at end
    }

    deinit {
        session.stopRunning()
    }

    // MARK: - Permissions

    public enum CameraPermissionError: LocalizedError {
        case cameraDenied, micDenied
        public var errorDescription: String? {
            switch self {
            case .cameraDenied: "Camera access is denied."
            case .micDenied:    "Microphone access is denied."
            }
        }
    }

    /// Request permissions for camera + mic if needed.
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

    // MARK: - Session setup / start / stop

    /// Prepare the session graph: front camera + mic → movie output.
    public func configureSession() async throws {
        try await requestPermissions()

        await runOnSessionQueue {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.session.sessionPreset = .hd1280x720

            // Clean previous inputs/outputs if reconfiguring
            if let vi = self.videoInput { self.session.removeInput(vi); self.videoInput = nil }
            if let ai = self.audioInput { self.session.removeInput(ai); self.audioInput = nil }
            if self.session.outputs.contains(self.movieOutput) { self.session.removeOutput(self.movieOutput) }

            // Video input: front wide camera
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                self.report(error: NSError(domain: "CameraRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Front camera unavailable"]))
                return
            }

            // Prefer 720p 30 fps for perf (best effort)
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                device.unlockForConfiguration()
            } catch {
                // Non-fatal
            }

            do {
                let vInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(vInput) { self.session.addInput(vInput); self.videoInput = vInput }
            } catch {
                self.report(error: error); return
            }

            // Audio input (built‑in mic)
            if let mic = AVCaptureDevice.default(for: .audio) {
                do {
                    let aInput = try AVCaptureDeviceInput(device: mic)
                    if self.session.canAddInput(aInput) { self.session.addInput(aInput); self.audioInput = aInput }
                } catch {
                    self.report(error: error); return
                }
            }

            // Output
            if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }

            // Initial connection tuning (mirror front cam, set rotation/orientation)
            if let conn = self.movieOutput.connection(with: .video) {
                self.configureConnectionRotation(conn)
                conn.isVideoMirrored = true
                if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .auto }
            }
        }
    }

    /// Start camera preview.
    public func startSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            self.updateMain { $0.isSessionRunning = true }
        }
    }

    /// Stop camera preview.
    public func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            self.updateMain { $0.isSessionRunning = false }
        }
    }

    // MARK: - Recording

    /// Begin recording to a temp .mov file. Use `stopRecording()` to end early, or it auto‑stops at `maxSeconds`.
    public func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction-\(UUID().uuidString).mov")

        sessionQueue.async {
            // Refresh rotation each time we start (user may have rotated)
            if let conn = self.movieOutput.connection(with: .video) {
                self.configureConnectionRotation(conn)
                conn.isVideoMirrored = true
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            self.updateMain { $0.isRecording = true }
        }
    }

    public func stopRecording() {
        sessionQueue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: - Rotation/orientation helpers

    /// Set connection rotation with modern API on iOS 17+, fallback to legacy orientation on ≤16.
    private func configureConnectionRotation(_ conn: AVCaptureConnection) {
        let iface = currentInterfaceOrientation()
        if #available(iOS 17.0, *) {
            // Convert interface orientation → rotation angle (degrees clockwise).
            // Portrait = 0°, LandscapeLeft = 90°, LandscapeRight = -90°, PortraitUpsideDown = 180°
            let angle: CGFloat
            switch iface {
            case .landscapeLeft:  angle = 90
            case .landscapeRight: angle = -90
            case .portraitUpsideDown: angle = 180
            default: angle = 0
            }
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
        } else {
            // iOS 16 and below: use deprecated but supported videoOrientation
            if conn.isVideoOrientationSupported {
                switch iface {
                case .landscapeLeft:  conn.videoOrientation = .landscapeLeft
                case .landscapeRight: conn.videoOrientation = .landscapeRight
                case .portraitUpsideDown: conn.videoOrientation = .portraitUpsideDown
                default: conn.videoOrientation = .portrait
                }
            }
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation) ?? .portrait
    }

    // MARK: - Queue hop helpers

    /// Await executing `work` on the session queue.
    private func runOnSessionQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { cont in
            sessionQueue.async {
                work()
                cont.resume()
            }
        }
    }

    /// Update published properties on main.
    private func updateMain(_ body: @escaping (CameraRecorder) -> Void) {
        DispatchQueue.main.async { body(self) }
    }

    private func report(error: Error) {
        updateMain {
            $0.lastError = error.localizedDescription
            $0.onFailed?(error)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput,
                           didStartRecordingTo fileURL: URL,
                           from connections: [AVCaptureConnection]) {
        // No‑op; UI already updated on start.
    }

    public func fileOutput(_ output: AVCaptureFileOutput,
                           didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection],
                           error: Error?) {
        // Delegate method is nonisolated; hop to main for UI callbacks.
        updateMain { me in
            me.isRecording = false
            if let error {
                me.lastError = error.localizedDescription
                me.onFailed?(error)
            } else {
                me.onFinished?(outputFileURL)
            }
        }
    }
}

// MARK: - SwiftUI preview view

/// A SwiftUI view that hosts the camera preview (fills its space).
public struct CameraPreviewView: UIViewRepresentable {
    private let layer: AVCaptureVideoPreviewLayer

    public init(layer: AVCaptureVideoPreviewLayer) { self.layer = layer }

    public func makeUIView(context: Context) -> PreviewHost {
        let v = PreviewHost()
        v.backgroundColor = .black
        layer.frame = v.bounds
        v.layer.addSublayer(layer)
        return v
    }

    public func updateUIView(_ uiView: PreviewHost, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }

    public final class PreviewHost: UIView {
        public override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
