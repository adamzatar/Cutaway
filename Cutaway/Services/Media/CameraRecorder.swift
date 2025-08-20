//
//  CameraRecorder.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import Foundation
@preconcurrency import AVFoundation   // quiet Sendable warnings from AVFoundation in Swift 6
import CoreMedia
import UIKit
import SwiftUI

/// Front‑/Back camera + mic recorder for reaction clips.
/// - iOS 16+
/// - 720p preset
/// - Safe for Swift 6 actor isolation
@MainActor
public final class CameraRecorder: NSObject, ObservableObject {

    // MARK: Published UI state (main-actor)
    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var usingFrontCamera: Bool = true

    // Torch state you can bind to in SwiftUI
    @Published public private(set) var isTorchAvailable: Bool = false
    @Published public private(set) var isTorchOn: Bool = false

    // Callbacks
    public var onFinished: ((URL) -> Void)?
    public var onFailed: ((Error) -> Void)?

    // MARK: Capture graph (touched only on sessionQueue)
    // Marked as nonisolated(unsafe) so @Sendable closures can access them on the queue.
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?

    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "CameraRecorder.session")

    /// Desired camera position (front by default).
    nonisolated(unsafe) private var desiredPosition: AVCaptureDevice.Position = .front

    /// Preview layer (safe to construct once)
    public let previewLayer: AVCaptureVideoPreviewLayer

    /// Hard cap per clip (seconds)
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
        movieOutput.movieFragmentInterval = .invalid
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSeconds, preferredTimescale: 600)
    }

    deinit {
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
        default: throw CameraPermissionError.cameraDenied
        }
        // Mic
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
            if !ok { throw CameraPermissionError.micDenied }
        default: throw CameraPermissionError.micDenied
        }
    }

    // MARK: Configure / Start / Stop

    /// Initial graph build (uses `desiredPosition`).
    public func configureSession() async throws {
        try await requestPermissions()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try self.rebuildGraphOnQueue(position: self.desiredPosition)
                    Task { @MainActor in
                        self.isSessionRunning = self.session.isRunning
                        self.usingFrontCamera = (self.desiredPosition == .front)
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

    // MARK: Camera switching

    /// Toggle front/back camera at runtime. Safe to call from main.
    public func toggleCamera() {
        sessionQueue.async { [self] in
            let newPos: AVCaptureDevice.Position = (desiredPosition == .front) ? .back : .front
            do {
                try self.rebuildGraphOnQueue(position: newPos)
                Task { @MainActor in
                    self.usingFrontCamera = (newPos == .front)
                }
            } catch {
                Task { @MainActor in self.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: Torch API

    /// Toggle torch on/off (best effort; only available on back camera with torch).
    public func toggleTorch() {
        sessionQueue.async { [self] in
            guard let device = self.videoInput?.device, device.hasTorch else {
                Task { @MainActor in
                    self.isTorchAvailable = false
                    self.isTorchOn = false
                }
                return
            }
            do {
                try device.lockForConfiguration()
                if device.torchMode == .on {
                    device.torchMode = .off
                } else {
                    let level = min(AVCaptureDevice.maxAvailableTorchLevel, 0.6)
                    try device.setTorchModeOn(level: level)
                }
                device.unlockForConfiguration()

                let on = (device.torchMode == .on)
                Task { @MainActor in self.isTorchOn = on }
            } catch {
                Task { @MainActor in self.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: Recording

    public func startRecording() {
        guard !isRecording else { return }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction-\(UUID().uuidString).mov")

        sessionQueue.async { [self] in
            self.applyConnectionOrientationOnQueue()
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

    // MARK: Internal: build / rebuild graph (sessionQueue only)

    /// Rebuild inputs/outputs for a given position. (sessionQueue only)
    nonisolated(unsafe) private func rebuildGraphOnQueue(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        // Clean previous
        if let vi = videoInput { session.removeInput(vi); videoInput = nil }
        if let ai = audioInput { session.removeInput(ai); audioInput = nil }
        if session.outputs.contains(movieOutput) { session.removeOutput(movieOutput) }

        // Camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        else {
            throw NSError(domain: "CameraRecorder", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Camera \(position == .front ? "front" : "back") unavailable"])
        }

        try? camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        camera.unlockForConfiguration()

        let vIn = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(vIn) { session.addInput(vIn); videoInput = vIn }

        // Mic
        if let mic = AVCaptureDevice.default(for: .audio) {
            let aIn = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(aIn) { session.addInput(aIn); audioInput = aIn }
        }

        // Output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        // Save desired position
        desiredPosition = position

        // Update orientation (done by hopping to main for angle, then back here)
        applyConnectionOrientationOnQueue()

        // Update torch availability (READ on queue, PUBLISH on main)
        let available = (camera.hasTorch && position == .back)
        Task { @MainActor in
            self.isTorchAvailable = available
            if !available { self.isTorchOn = false }
        }
    }

    // MARK: Orientation helpers

    /// Read UI orientation on the main actor.
    @MainActor private func currentVideoRotationAngleMainActor() -> CGFloat {
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:      return 90
        case .landscapeRight:     return 270
        case .portraitUpsideDown: return 180
        default:                  return 0
        }
    }

    /// Compute angle on main, then apply to connection on the session queue.
    nonisolated(unsafe) private func applyConnectionOrientationOnQueue() {
        // Ask main for angle (UIKit), then come back to the capture queue
        Task { @MainActor in
            let angle = self.currentVideoRotationAngleMainActor()
            // hop back to session queue to touch AV connections
            self.sessionQueue.async { [self] in
                guard let conn = self.movieOutput.connection(with: .video) else { return }
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
                // Mirror only for front cam
                conn.isVideoMirrored = (self.desiredPosition == .front)
                if conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .auto
                }
            }
        }
    }

    // MARK: Torch utilities

    /// Update `isTorchAvailable` & `isTorchOn` from a given device (must publish on main).
    @MainActor private func updateTorchAvailability(for device: AVCaptureDevice) {
        let available = (device.hasTorch && desiredPosition == .back)
        self.isTorchAvailable = available
        if available {
            self.isTorchOn = (device.torchMode == .on)
        } else {
            self.isTorchOn = false
        }
    }
}

// MARK: - Delegate

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

// MARK: - SwiftUI preview layer host

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

// MARK: - File-scope helpers (not nested inside a function)

fileprivate func DBtoLinear(_ db: Float) -> Float {
    powf(10.0, db / 20.0)
}
