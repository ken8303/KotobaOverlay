import Foundation
import ScreenCaptureKit
import Speech
import AVFoundation
import CoreMedia

func matchingSpeechLocale(_ code: String, supported: [Locale]) -> Locale? {
    let wanted = Locale.Language(identifier: code)
    return supported.first { $0.identifier.replacingOccurrences(of: "_", with: "-") == code }
        ?? supported.sorted { $0.identifier < $1.identifier }.first {
            $0.language.languageCode == wanted.languageCode &&
            (wanted.script == nil || $0.language.script == wanted.script)
        }
}

/// Serial audio conversion feeds Apple's on-device analyzer; microphone is never captured.
final class AppAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Kotoba.appAudio")
    @MainActor private let shutdown = AudioShutdown()
    private var stream: SCStream?
    private var analyzer: SpeechAnalyzer?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var audioTimeline = AudioTimeline()
    private var active = false
    var onCue: (@Sendable (TimedSubtitle) async -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?

    static func supportedLocales() async -> [Locale] {
        let speech = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocales : []
        return speech + (await DictationTranscriber.supportedLocales)
    }
    @MainActor func start(application: SCRunningApplication, display: SCDisplay, locale code: String) async throws {
        let module: any SpeechModule
        let speech: SpeechTranscriber?
        let dictation: DictationTranscriber?
        let modernLocales = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocales : []
        if let locale = matchingSpeechLocale(code, supported: modernLocales) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            module = transcriber; speech = transcriber; dictation = nil
        } else if let locale = matchingSpeechLocale(code, supported: await DictationTranscriber.supportedLocales) {
            let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [.frequentFinalization], attributeOptions: [.audioTimeRange])
            module = transcriber; dictation = transcriber; speech = nil
        } else {
            throw problem("No on-device speech model supports \(code) on this Mac. Refresh speech languages and choose one listed as supported.")
        }
        onStatus?("Checking speech model for \(code)…")
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                onStatus?("Downloading speech model for \(code)… Internet is needed for this download; audio stays on this Mac.")
                try await installation.downloadAndInstall()
            }
        } catch { throw problem("Speech model setup failed for \(code): \(error.localizedDescription). Check your internet connection and free disk space, then retry.") }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw problem("The speech model has no compatible audio format on this Mac.")
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        self.analyzer = analyzer
        let inputs = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(200))
        await withCheckedContinuation { done in
            queue.async { self.format = format; self.converter = nil; self.continuation = inputs.continuation; self.active = true; done.resume() }
        }
        resultsTask = Task { [weak self] in
            do {
                if let speech {
                    for try await result in speech.results { await self?.emit(text: String(result.text.characters), range: result.range) }
                } else if let dictation {
                    for try await result in dictation.results { await self?.emit(text: String(result.text.characters), range: result.range) }
                }
            } catch { if !Task.isCancelled { self?.onFailure?("Speech recognition failed: \(error.localizedDescription)") } }
        }
        analysisTask = Task { [weak self] in
            do {
                _ = try await analyzer.analyzeSequence(inputs.stream)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                // analyzeSequence has already terminated the analyzer on failure.
                self?.resultsTask?.cancel()
                if !Task.isCancelled {
                    self?.queue.async { [weak self] in self?.fail("Speech analysis failed: \(error.localizedDescription)") }
                }
            }
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true; config.captureMicrophone = false
        config.excludesCurrentProcessAudio = true; config.sampleRate = 48000; config.channelCount = 1
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch { await stop(); throw error }
    }
    @MainActor func stop() async {
        await shutdown.run { await self.finishCapture() }
    }
    @MainActor private func finishCapture() async {
        if let stream { try? await stream.stopCapture() }; stream = nil
        await withCheckedContinuation { done in
            queue.async { self.active = false; self.continuation?.finish(); self.continuation = nil; done.resume() }
        }
        await analysisTask?.value; await resultsTask?.value
        analysisTask = nil; resultsTask = nil; analyzer = nil
    }
    private func emit(text: String, range: CMTimeRange) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = range.start.seconds, end = range.end.seconds
        guard !clean.isEmpty, start.isFinite, end.isFinite, end > start else { return }
        await onCue?(TimedSubtitle(start: start, end: end, original: clean))
    }
    private func problem(_ text: String) -> NSError {
        NSError(domain: "KotobaSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              sampleBuffer.numSamples > 0, let description = sampleBuffer.formatDescription, let format else { return }
        let pts = sampleBuffer.presentationTimeStamp
        guard pts.isNumeric else { return }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else { return }
        pcm.frameLength = pcm.frameCapacity
        let code = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList)
        guard code == noErr else { fail("Could not read captured audio (\(code))."); return }
        if converter?.inputFormat != inputFormat { converter = AVAudioConverter(from: inputFormat, to: format) }
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(pcm.frameLength) * format.sampleRate / inputFormat.sampleRate)) + 32) else { fail("Audio conversion is unavailable."); return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return pcm
        }
        if let error { fail(error.localizedDescription); return }
        guard output.frameLength > 0 else { return }
        guard let start = audioTimeline.startTime(captureTime: pts, outputFrames: Int(output.frameLength), sampleRate: Int32(format.sampleRate.rounded())) else {
            fail("The captured audio has an invalid timestamp or sample rate."); return
        }
        let input = AnalyzerInput(buffer: output, bufferStartTime: start)
        if case .dropped = continuation?.yield(input) {
            fail("Speech processing fell behind. Capture stopped to avoid silently losing audio; finish and export this timeline.")
        }
    }
    private func fail(_ message: String) { active = false; continuation?.finish(); onFailure?(message) }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?("Audio capture stopped: \(error.localizedDescription)") }
}
