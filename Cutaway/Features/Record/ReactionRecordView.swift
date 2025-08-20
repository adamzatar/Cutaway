//
//  ReactionRecordView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//


import SwiftUI
import AVFoundation
import UIKit

struct ReactionRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinish: (URL) -> Void

    @StateObject private var rec = CameraRecorder()
    @State private var errorMsg: String?
    @State private var isReady = false

    var body: some View {
        ZStack {
            // PREVIEW
            if isReady {
                CameraPreviewView(layer: rec.previewLayer)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale))
            } else {
                Color.black.ignoresSafeArea()
                ProgressView("Preparing camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            // OVERLAYS
            VStack {
                // Top bar
                HStack(spacing: 12) {
                    // Close
                    CircleButton(
                        system: "xmark",
                        size: 34,
                        bg: .ultraThinMaterial,
                        fg: .white
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        rec.stopSession()
                        dismiss()
                    }

                    Spacer()

                    // Torch (only when available, i.e. back camera)
                    if rec.isTorchAvailable {
                        CircleToggleButton(
                            isOn: rec.isTorchOn,
                            onIcon: "bolt.fill",
                            offIcon: "bolt.slash",
                            size: 34,
                            bgOn: Color.yellow.opacity(0.25),
                            bgOff: .ultraThinMaterial,
                            fgOn: .yellow,
                            fgOff: .white
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            rec.toggleTorch()
                        }
                        .disabled(!isReady)
                        .opacity(isReady ? 1 : 0.3)
                    }

                    // Flip camera
                    CircleButton(
                        system: "arrow.triangle.2.circlepath.camera",
                        size: 34,
                        bg: .ultraThinMaterial,
                        fg: .white
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        rec.toggleCamera()
                    }
                    .disabled(!isReady)
                    .opacity(isReady ? 1 : 0.3)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()

                // Bottom controls
                HStack(spacing: 28) {
                    // Record
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if rec.isRecording { rec.stopRecording() }
                        else { rec.startRecording() }
                    } label: {
                        RecordButton(isRecording: rec.isRecording)
                    }
                    .disabled(!isReady)

                    // Done / Accept
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        rec.stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(rec.isRecording ? 0.25 : 1)
                    }
                    .disabled(rec.isRecording)
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            // Prepare recorder and start preview
            do {
                rec.onFinished = { url in
                    Task { @MainActor in
                        onFinish(url)
                        rec.stopSession()
                        dismiss()
                    }
                }
                rec.onFailed = { err in
                    Task { @MainActor in errorMsg = err.localizedDescription }
                }

                try await rec.configureSession()
                rec.startSession()
                isReady = true
            } catch {
                errorMsg = error.localizedDescription
            }
        }
        .onDisappear { rec.stopSession() }
        .alert("Camera Error", isPresented: Binding(
            get: { errorMsg != nil },
            set: { _ in errorMsg = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMsg ?? "Unknown error")
        }
    }
}

// MARK: - Pretty Record Button (ring + core)
private struct RecordButton: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            // Outer glossy ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 6
                )
                .frame(width: 86, height: 86)
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)

            // Soft glow
            Circle()
                .fill(Color.white.opacity(isRecording ? 0.12 : 0.18))
                .frame(width: 100, height: 100)
                .blur(radius: 8)
                .opacity(isRecording ? 0.25 : 0.35)

            // Core
            Group {
                if isRecording {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 36, height: 36)
                        .shadow(color: .red.opacity(0.35), radius: 6, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 66, height: 66)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.5), lineWidth: 1)
                                .blur(radius: 1)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}

// MARK: - Small UI Helpers
private struct CircleButton: View {
    let system: String
    let size: CGFloat
    let bg: Material
    let fg: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(bg)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
    }
}

private struct CircleToggleButton: View {
    let isOn: Bool
    let onIcon: String
    let offIcon: String
    let size: CGFloat
    let bgOn: Color
    let bgOff: Material
    let fgOn: Color
    let fgOff: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? onIcon : offIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? fgOn : fgOff)
                .frame(width: size, height: size)
                // ✅ Make both branches the same type using AnyShapeStyle
                .background(isOn
                            ? AnyShapeStyle(bgOn)
                            : AnyShapeStyle(bgOff))
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
    }
}

#Preview {
    ReactionRecordView(onFinish: { _ in })
}
