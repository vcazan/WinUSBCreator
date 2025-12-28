import SwiftUI

// This file is kept for potential future use but the main UI is now in ContentView.swift
// Progress display is handled inline in ContentView.

struct CreationProgressView: View {
    let state: CreationState
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: state.progress) {
                Text(state.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
        }
    }
}

#Preview {
    CreationProgressView(state: .copying(progress: 0.45, currentFile: "install.wim", bytesCopied: 2_500_000_000, totalBytes: 5_500_000_000))
        .padding()
        .frame(width: 400)
}
