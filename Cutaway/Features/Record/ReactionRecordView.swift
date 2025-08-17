//
//  ReactionRecordView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import SwiftUI
import AVFoundation

struct ReactionRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinish: (URL) -> Void

    @StateObject private var rec = CameraRecorder()
    @State private var errorMsg: String?
    @State private var isReady = false

    var body: some View {
        ZStack {
            if isReady {
                CameraPreviewView(layer: rec.previewLayer)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                ProgressView("Preparing camera…").tint(.white)
            }

            VStack {
                HStack {
                    Button {
                        rec.stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 24) {
                    Button {
                        if rec.isRecording { rec.stopRecording() } else { rec.startRecording() }
                    } label: {
                        ZStack {
                            Circle().fill(rec.isRecording ? .red : .white)
                                .frame(width: 72, height: 72)
                                .shadow(radius: 6)
                            if rec.isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }

                    Button {
                        rec.stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .opacity(rec.isRecording ? 0.3 : 1)
                    }
                    .disabled(rec.isRecording)
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            // Prepare recorder and start preview. Errors surface as alert.
            do {
                rec.onFinished = { url in onFinish(url) }
                rec.onFailed = { err in errorMsg = err.localizedDescription }
                try await rec.configureSession()
                rec.startSession()
                isReady = true
            } catch {
                errorMsg = error.localizedDescription
            }
        }
        .onDisappear {
            rec.stopSession()
        }
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

#Preview {
    ReactionRecordView(onFinish: { _ in })
}
