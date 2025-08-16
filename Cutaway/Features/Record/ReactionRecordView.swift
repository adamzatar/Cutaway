//
//  ReactionRecordView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import SwiftUI

struct ReactionRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rec = CameraRecorder()

    let onFinish: (URL) -> Void

    var body: some View {
        ZStack {
            CameraPreviewView(layer: rec.previewLayer)
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(.black.opacity(0.35), in: Circle())
                    }

                    Button {
                        if rec.isRecording { rec.stopRecording() } else { rec.startRecording() }
                    } label: {
                        Circle()
                            .fill(rec.isRecording ? .red : .white)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 2))
                    }

                    Button {
                        // toggle front/back later if needed
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            do {
                try await rec.configureSession()
                rec.startSession()
                rec.onFinished = { url in
                    onFinish(url)
                    dismiss()
                }
                rec.onFailed = { _ in
                    dismiss()
                }
            } catch {
                dismiss()
            }
        }
        .onDisappear {
            rec.stopSession()
        }
    }
}

#Preview {
    ReactionRecordView { url in
        print("Recorded to: \(url)")
    }
}
