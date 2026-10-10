import AVFoundation
import Foundation
import Observation
import Speech

// Live on-device transcription with iOS 26's SpeechAnalyzer + SpeechTranscriber
@Observable
final class SpeechRecorder {
    private(set) var finalized = ""
    private(set) var volatile = ""      // in-progress guess that can still change
    private(set) var isRecording = false
    private(set) var isPreparing = false
    var errorMessage: String?

    var transcript: String {
        [finalized, volatile].joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    enum RecorderError: LocalizedError {
        case micDenied, unsupportedLocale, noAudioFormat
        var errorDescription: String? {
            switch self {
            case .micDenied: "Layer needs microphone access. You can turn it on in Settings."
            case .unsupportedLocale: "On-device speech isn't available for your language yet."
            case .noAudioFormat: "Couldn't set up the microphone."
            }
        }
    }

    func start() async {
        guard !isRecording, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        finalized = ""
        volatile = ""
        errorMessage = nil

        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.micDenied }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw RecorderError.unsupportedLocale
            }

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )

            // First run downloads the speech model. After that it's fully offline.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw RecorderError.noAudioFormat
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            self.inputBuilder = builder

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.receive(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }

            try await analyzer.start(inputSequence: stream)
            try await startEngine(feeding: builder, as: format)
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            await stop()
        }
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += (finalized.isEmpty ? "" : " ") + text
            volatile = ""
        } else {
            volatile = text
        }
    }

    func stop() async {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        inputBuilder?.finish()
        // Flush whatever was still "volatile" into final text before we read it
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        analyzer = nil
        inputBuilder = nil
        resultsTask = nil
        isRecording = false
        try? await Self.setSessionActive(false)
    }

    private func startEngine(feeding builder: AsyncStream<AnalyzerInput>.Continuation, as format: AVAudioFormat) async throws {
        try await Self.setSessionActive(true)

        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: format) else { throw RecorderError.noAudioFormat }

        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat, block: Self.makeTap(converter: converter, format: format, builder: builder))
        engine.prepare()
        try engine.start()
    }

    // Turning the audio session on or off can block for a moment while the system
    // reroutes audio, so it runs on a background thread instead of freezing the UI
    nonisolated private static func setSessionActive(_ active: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if active {
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }.value
    }

    // Built in a nonisolated context on purpose: the tap fires on a realtime audio thread,
    // and a main-actor closure there trips Swift's isolation check and crashes
    nonisolated private static func makeTap(
        converter: AVAudioConverter,
        format: AVAudioFormat,
        builder: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let converted = convert(buffer, with: converter, to: format) {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    // Mic is usually 48kHz stereo; the transcriber wants its own format (often 16kHz mono)
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}
