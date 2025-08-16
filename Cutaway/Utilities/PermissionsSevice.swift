//
//  PermissionsSevice.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import AVFoundation
import Photos
import Foundation
import UIKit

/// Centralized helpers for camera/mic/Photos (Add) permissions.
/// Note: PHPicker does NOT require read permission; we only ask for Photos *add* when exporting.
public enum PermissionsService {

    // MARK: Camera

    public static func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Request camera permission if needed. Returns `true` if authorized.
    public static func requestCameraIfNeeded() async -> Bool {
        switch cameraAuthorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    cont.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: Microphone

    public static func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Request mic permission if needed. Returns `true` if authorized.
    public static func requestMicrophoneIfNeeded() async -> Bool {
        switch microphoneAuthorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: Photos (Add‑only)

    public static func photosAddAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    /// Request Photos *add* permission if needed. Returns `true` if authorized or limited.
    public static func requestPhotosAddIfNeeded() async -> Bool {
        switch photosAddAuthorizationStatus() {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    cont.resume(returning: status == .authorized || status == .limited)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: Convenience bundles

    /// Ask for both camera & mic; return `true` only if both are granted.
    /// (Sequential awaits to avoid 'async let' diagnostics in some contexts.)
    public static func ensureRecordingPermissions() async -> Bool {
        let cam = await requestCameraIfNeeded()
        let mic = await requestMicrophoneIfNeeded()
        return cam && mic
    }

    /// Ask for Photos add‑permission; used right before saving the exported MP4.
    public static func ensurePhotosAddPermission() async -> Bool {
        await requestPhotosAddIfNeeded()
    }

    // MARK: Settings deep link

    /// Open the app’s Settings page.
    @MainActor
    public static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
