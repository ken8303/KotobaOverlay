import AppKit
import SwiftUI
import Speech
import ScreenCaptureKit
import Translation
import UniformTypeIdentifiers

@MainActor final class LiveAudioModel: ObservableObject {
    @Published var speechLocales: [Locale] = []
    @Published var checkingSpeech = false
    func supportsSpeech(_ code: String) -> Bool { matchingSpeechLocale(code, supported: speechLocales) != nil }
    func refreshSpeechLanguages() async {
        checkingSpeech = true
        speechLocales = await AppAudioCapture.supportedLocales()
        checkingSpeech = false
        if speechLocales.isEmpty { status = "Apple's on-device speech service reported no supported languages. Restart the Mac, then refresh speech languages." }
        else if !supportsSpeech(source) { status = "The selected source language is not supported for on-device speech on this Mac. Choose an available source language." }
    }
    @Published var confirmClear = false
    @Published var applications: [SCRunningApplication] = []
    @Published var selectedPID: Int32 = 0
    @Published var source = "ja"
    @Published var target = "zh-Hant"
    @Published var busy = false
    @Published var capturing = false
    @Published var stopping = false
    @Published var status = "Choose the application playing your video."
    @Published var cues: [TimedSubtitle] = []
    @Published var firstTimestamp = ""
    @Published var textMode: SubtitleTextMode = .both { didSet { refreshSubtitle() } }
    @Published var configuration: TranslationSession.Configuration?
    @Published var subtitle = ""
    @Published var showOverlay = true { didSet { updateOverlay() } }
    private var recorder = AppAudioCapture()
    private var display: SCDisplay?
    private var panel: NSPanel?
    private var generation = 0
    private var stopRequested = false
    private var captureFailure: String?
    private var displayedCue: UUID?
    private var overlayExpiry: Task<Void, Never>?
    private var sessionSource: String?
    private var sessionTarget: String?

    func refreshApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            applications = content.applications.filter { $0.processID != ProcessInfo.processInfo.processIdentifier && !$0.applicationName.isEmpty }.sorted { $0.applicationName < $1.applicationName }
            display = content.displays.first
        } catch { status = "Allow Screen & System Audio Recording for Kotoba: \(error.localizedDescription)" }
    }
    func start() {
        guard !busy, selectedPID != 0, supportsSpeech(source) else { return }
        if !cues.isEmpty && (sessionSource != source || sessionTarget != target) {
            status = "Start a new timeline before changing languages."; return
        }
        busy = true; stopRequested = false; captureFailure = nil; generation += 1; let current = generation
        status = "Checking speech permission…"
        Task {
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard current == generation else { return }
            if stopRequested { busy = false; status = "Cancelled."; return }
            guard authorization == .authorized else { busy = false; status = "Enable Speech Recognition for Kotoba in System Settings → Privacy & Security."; return }
            configuration = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target), preferredStrategy: .lowLatency)
            configuration?.invalidate()
        }
    }
    func run(using session: TranslationSession) async {
        let current = generation
        do {
            status = "Preparing translation languages…"
            try await session.prepareTranslation()
            try Task.checkCancellation()
            if stopRequested { throw CancellationError() }
            guard current == generation else { return }
            guard let app = applications.first(where: { $0.processID == selectedPID }), let display else {
                throw NSError(domain: "Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh the application list and select your player."])
            }
            sessionSource = source; sessionTarget = target
            recorder.onStatus = { [weak self] message in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.status = message
                }
            }
            recorder.onCue = { [weak self] cue in
                await MainActor.run {
                    guard let self, self.generation == current else { return }
                    self.cues.append(cue)
                    self.cues.sort { $0.start < $1.start }
                    if self.cues.filter({ $0.translated == nil }).count >= 100 {
                        self.status = "Translation is falling behind. Capture paused; finishing queued cues."
                        self.stop()
                    }
                }
            }
            recorder.onFailure = { [weak self] message in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.captureFailure = message; self.status = message; self.stop()
                }
            }
            try await recorder.start(application: app, display: display, locale: source)
            guard current == generation, !Task.isCancelled, !stopRequested else { throw CancellationError() }
            capturing = true; status = "Listening to \(app.applicationName) · microphone off"
            while current == generation && !Task.isCancelled {
                if let index = cues.firstIndex(where: { $0.translated == nil }) {
                    let id = cues[index].id
                    let response = try await session.translate(cues[index].original)
                    guard current == generation, let slot = cues.firstIndex(where: { $0.id == id }) else { return }
                    cues[slot].translated = response.targetText
                    displayedCue = id
                    refreshSubtitle()
                    overlayExpiry?.cancel()
                    overlayExpiry = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(6)) } catch { return }
                        self?.displayedCue = nil; self?.subtitle = ""; self?.panel?.orderOut(nil)
                    }
                } else if !capturing && !stopping { break }
                else { try await Task.sleep(for: .milliseconds(100)) }
            }
            if current == generation { status = captureFailure ?? "Stopped · \(cues.count) timed cues ready to export." }
        } catch {
            if current == generation { status = "Audio subtitles: \(error.localizedDescription)" + (cues.contains { $0.translated == nil } ? " Untranslated cues can be exported as Original." : "") }
        }
        await recorder.stop()
        if current == generation { capturing = false; busy = false; stopping = false; clearOverlay() }
    }
    func stop() {
        guard !stopping else { return }
        if !capturing {
            if busy { stopRequested = true; configuration = nil; status = "Cancelling…" }
            panel?.orderOut(nil); return
        }
        stopping = true
        let current = generation
        Task {
            await recorder.stop()
            guard current == generation else { return }
            capturing = false; stopping = false
        }
    }
    func newTimeline() {
        guard !busy else { return }
        generation += 1; recorder = AppAudioCapture(); cues = []; firstTimestamp = ""; subtitle = ""
        sessionSource = nil; sessionTarget = nil; clearOverlay()
        status = "New timeline. Start playback and capture together."
    }
    func export() {
        do {
            let first = firstTimestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try SubtitleTimeline.parse(firstTimestamp)
            let text = try SubtitleTimeline.srt(cues, firstStart: first, mode: textMode)
            let save = NSSavePanel(); save.nameFieldStringValue = "Kotoba-Subtitles.srt"
            save.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
            save.begin { response in
                guard response == .OK, let url = save.url else { return }
                do { try text.write(to: url, atomically: true, encoding: .utf8) }
                catch { Task { @MainActor in self.status = "Export failed: \(error.localizedDescription)" } }
            }
        } catch { status = error.localizedDescription }
    }
    private func clearOverlay() {
        overlayExpiry?.cancel(); overlayExpiry = nil; displayedCue = nil; subtitle = ""; panel?.orderOut(nil)
    }
    private func refreshSubtitle() {
        guard let id = displayedCue, let cue = cues.first(where: { $0.id == id }) else { return }
        switch textMode {
        case .original: subtitle = cue.original
        case .translated: subtitle = cue.translated ?? ""
        case .both: subtitle = cue.original + "\n" + (cue.translated ?? "")
        }
        updateOverlay()
    }
    private func updateOverlay() {
        guard busy, showOverlay, !subtitle.isEmpty, let screen = NSScreen.main else { panel?.orderOut(nil); return }
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.ignoresMouseEvents = true; p.hidesOnDeactivate = false; panel = p
        }
        let width = min(900, screen.visibleFrame.width - 40)
        panel?.setFrame(CGRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 45, width: width, height: 150), display: true)
        panel?.contentView = NSHostingView(rootView: Text(subtitle).font(.system(size: 26, weight: .medium)).multilineTextAlignment(.center).foregroundStyle(.white).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 12)))
        panel?.orderFrontRegardless()
    }
}
