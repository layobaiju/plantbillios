import AVFoundation
import Combine
import Foundation
import Speech

/// Live microphone dictation for the bill screen's product search.
///
/// Android gets this for free from `RecognizerIntent` — the system's
/// full-screen "Speak now" dialog, which also handles its own permission. iOS
/// has no equivalent system UI, so the app has to run `SFSpeechRecognizer`
/// itself and present its own listening sheet; that is what
/// `VoiceSearchButton` draws.
///
/// Locale is en-IN to match Android's `EXTRA_LANGUAGE`, and up to 6
/// alternative transcriptions are returned (Android asks for
/// `EXTRA_MAX_RESULTS = 6`) so the caller can pick whichever snaps closest to
/// a real product name.
@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Failure: Equatable {
        /// Permission denied, or speech recognition unavailable on this device.
        case unavailable
        case failed
    }

    @Published private(set) var isListening = false
    /// What has been heard so far, shown live while the sheet is open.
    @Published private(set) var partialTranscript = ""
    @Published private(set) var failure: Failure?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    /// Every alternative heard, best first. Empty until the session stops.
    private(set) var alternatives: [String] = []

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func start() async {
        guard await requestPermissions() else {
            failure = .unavailable
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            failure = .unavailable
            return
        }

        stopAudio()
        alternatives = []
        partialTranscript = ""
        failure = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            failure = .failed
            stopAudio()
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    // Keep the alternatives up to date as we go, so stopping
                    // mid-sentence still has something to match against.
                    self.alternatives = Array(
                        result.transcriptions.prefix(6).map(\.formattedString)
                    )
                }
                if error != nil || result?.isFinal == true {
                    self.finish()
                }
            }
        }
    }

    /// Ends the session. Any alternatives gathered so far stay available for
    /// the caller to match on.
    func stop() {
        finish()
    }

    private func finish() {
        guard isListening || engine.isRunning else { return }
        isListening = false
        stopAudio()
    }

    private func stopAudio() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        return await withCheckedContinuation { continuation in
            // AVAudioApplication is iOS 17+; this app supports iOS 16, so the
            // AVAudioSession call stays.
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
