import SwiftUI

/// Mic button beside the bill screen's product search, mirroring Android's
/// `VoiceSearchButton`. Android can hand off to the system's "Speak now"
/// dialog; iOS has no such thing, so tapping this opens a listening sheet that
/// shows what is being heard and a big Done button — deliberately large and
/// plain-spoken, since the audience is elderly shop owners.
///
/// Delivers ALL alternative transcripts so the caller can snap to the closest
/// product name rather than doing a literal text search.
struct VoiceSearchButton: View {
    let onResults: ([String]) -> Void
    let onUnavailable: () -> Void

    @StateObject private var recognizer = SpeechRecognizer()
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
            Task { await recognizer.start() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PlantbillColor.green)
                .frame(width: PlantbillSpacing.minTouchTarget, height: PlantbillSpacing.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice search")
        .sheet(isPresented: $isPresented) {
            listeningSheet
                .presentationDetents([.height(320)])
        }
        .onChange(of: recognizer.failure) { failure in
            guard failure != nil else { return }
            isPresented = false
            onUnavailable()
        }
    }

    private var listeningSheet: some View {
        VStack(spacing: PlantbillSpacing.lg) {
            Text("Say the plant name")
                .font(PlantbillTypography.headline)
                .foregroundStyle(PlantbillColor.textPrimary)

            Image(systemName: recognizer.isListening ? "waveform" : "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(PlantbillColor.green)
                .symbolEffectIfAvailable(active: recognizer.isListening)

            Text(recognizer.partialTranscript.isEmpty ? "Listening…" : recognizer.partialTranscript)
                .font(PlantbillTypography.body)
                .foregroundStyle(
                    recognizer.partialTranscript.isEmpty
                        ? PlantbillColor.textSecondary
                        : PlantbillColor.textPrimary
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineLimit(2)

            PrimaryButton(title: "Done") { finish() }

            SecondaryButton(title: "Cancel") {
                recognizer.stop()
                isPresented = false
            }
        }
        .padding(PlantbillSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlantbillColor.background)
        .onDisappear { recognizer.stop() }
    }

    private func finish() {
        recognizer.stop()
        // Fall back to the live partial when the recogniser hasn't produced a
        // final alternatives list yet — stopping early is the common case.
        var phrases = recognizer.alternatives
        if phrases.isEmpty, !recognizer.partialTranscript.isEmpty {
            phrases = [recognizer.partialTranscript]
        }
        isPresented = false
        guard !phrases.isEmpty else { return }
        onResults(phrases)
    }
}

private extension View {
    /// `symbolEffect` is iOS 17+; the app targets iOS 16, so the pulse is a
    /// bonus on newer devices rather than a requirement.
    @ViewBuilder
    func symbolEffectIfAvailable(active: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.variableColor, isActive: active)
        } else {
            self
        }
    }
}
