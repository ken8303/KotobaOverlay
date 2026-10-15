import AppKit
import SwiftUI
import Translation
import Vision
import UniformTypeIdentifiers
import ApplicationServices

@MainActor final class AppModel: ObservableObject {
    @Published var showAudio = false
    @Published var videoMode = false { didSet {
        guard videoMode != oldValue else { return }
        stop(); selection = nil; selectedWindow = ""; areaScreen = nil; areaRect = nil; areaFrame.hide()
        status = videoMode ? "Draw only the video picture, excluding the webpage and player controls." : "Choose a capture area to begin."
    } }
    @Published var subtitlesOnly = true { didSet {
        guard subtitlesOnly != oldValue, videoMode else { return }
        let resume = running
        // Tracked video crops are recomputed by the capture loop after restart.
        stop()
        if resume { start() }
    } }
    private var effectiveAreaRect: CGRect? {
        areaRect.map { videoCaptureRect($0, subtitlesOnly: videoMode && subtitlesOnly) }
    }
    func updateScreenAreaCrop() {
        guard !videoMode else { return }
        guard let screen = areaScreen, let rect = effectiveAreaRect, let old = selection else { return }
        selection = CaptureChoice(id: old.id, name: "Screen area", window: nil, display: old.display, crop: captureCrop(rect, screenHeight: screen.frame.height))
    }
    func selectVideo() { videoMode = true; selectRegion() }
    @Published var excludeInputFields = true
    @Published var inputDetectionAuthorized = inputFieldDetectionAvailable()
    @Published var screenAuthorized = CGPreflightScreenCaptureAccess()
    private var requestedScreenAccess = false
    private var didLoad = false
    @Published var source = UserDefaults.standard.string(forKey: "source") ?? "ja"
    @Published var target = UserDefaults.standard.string(forKey: "target") ?? "zh-Hant"
    @Published var languages: [String] = []
    @Published var ocrLanguages: [String] = []
    @Published var windows: [CaptureChoice] = []
    @Published var selectedWindow = "" { didSet { if !selectedWindow.isEmpty { useWindow() } } }
    @Published var selection: CaptureChoice?
    @Published var editingArea = false
    @Published var areaFrameVisible = true
    private var areaScreen: NSScreen?
    private var areaRect: CGRect?
    private var resumeAfterAreaEdit = false
    private let areaFrame = RegionFrameController()
    @Published var status = "Choose a capture area to begin."
    @Published var running = false
    @Published var original = ""
    @Published var translated = ""
    @Published var fontSize = 28.0 { didSet { refreshOverlayAppearance() } }
    @Published var opacity = 1.0 { didSet { refreshOverlayAppearance() } }
    @Published var positionedTranslations: [PositionedTranslation] = []
    var translationFrame: CGRect?
    private var latestLines: [OCRLine] = []
    @Published var showOriginal = UserDefaults.standard.bool(forKey: "showOriginal") { didSet { UserDefaults.standard.set(showOriginal, forKey: "showOriginal"); refreshPositionedTranslations() } }
    @Published private(set) var historyCount = 0
    private var history = TranslationHistory()
    @Published var editOverlay = false { didSet { if overlayVisible { overlay.show(model: self) } } }
    @Published var overlayVisible = false
    @Published var configuration: TranslationSession.Configuration?
    @Published var recognitionReady = false
    private var startAfterDownload = false
    private var warmedLanguage: String?
    @Published var pairInstalled = false
    @Published var preparing = false
    private let hotkeys = HotKeys()
    private let capture = CaptureService()
    private let overlay = OverlayController()
    private let selector = RegionSelector()
    private var loop: Task<Void, Never>?
    private var lineRetry = OCRRetryState()
    private var translationTask: Task<Void, Never>?
    private var retryTranslationAfter = Date.distantPast
    private var session: TranslationSession?
    private var revision = 0
    private var stopRevision = 0
    private var cache = TranslationCache()
    private var languageRevision = 0
    var sourceOptions: [String] { languages.filter { ocrCode(for: $0) != nil } }
    func label(_ code: String) -> String {
        let language = Locale.Language(identifier: code)
        if language.languageCode?.identifier == "zh" {
            return language.script?.identifier == "Hant" ? "Traditional Chinese (繁體中文)" : "Simplified Chinese (简体中文)"
        }
        return Locale.current.localizedString(forIdentifier: code) ?? code
    }
    func ocrCode(for code: String) -> String? {
        let language = Locale.Language(identifier: code)
        return ocrLanguages.first { candidate in
            let other = Locale.Language(identifier: candidate)
            return language.languageCode == other.languageCode && (language.script == nil || other.script == language.script)
        }
    }
    func load() async {
        guard !didLoad else { return }
        didLoad = true
        hotkeys.register { [weak self] id in
            guard let self else { return }
            switch id {
            case 1: self.running ? self.stop() : self.start()
            case 2: self.toggleOverlay()
            case 3: self.selectRegion()
            case 4: self.toggleAreaEditing()
            default: break
            }
        }
        let available = await Task.detached {
            await LanguageAvailability(preferredStrategy: .lowLatency).supportedLanguages.map { $0.minimalIdentifier }
        }.value
        languages = available.sorted { label($0) < label($1) }
        ocrLanguages = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        if !languages.contains(target) {
            let wanted = Locale.Language(identifier: target)
            if let equivalent = languages.first(where: {
                let candidate = Locale.Language(identifier: $0)
                return candidate.languageCode == wanted.languageCode && candidate.script == wanted.script
            }) { target = equivalent }
        }
        await checkPair()
    }
    func checkPair() async {
        stop(); pairInstalled = false; recognitionReady = false; configuration = nil; preparing = false
        languageRevision += 1; let generation = languageRevision
        UserDefaults.standard.set(source, forKey: "source"); UserDefaults.standard.set(target, forKey: "target")
        cache.removeAll()
        guard sourceOptions.contains(source), languages.contains(target) else { status = "This language is unavailable for screen translation on this Mac."; return }
        let state = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
        guard generation == languageRevision else { return }
        guard let code = ocrCode(for: source) else { return }
        if warmedLanguage != code {
            recognitionReady = false
            status = "Preparing on-device text recognition…"
            do {
                let sample = NSImage(size: NSSize(width: 240, height: 64), flipped: false) { rect in
                    NSColor.black.setFill(); rect.fill()
                    ("字幕 Text" as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.white])
                    return true
                }
                if let bitmap = sample.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    _ = try await CaptureService.recognize(bitmap, language: code)
                }
                guard generation == languageRevision else { return }
                warmedLanguage = code; recognitionReady = true
            } catch {
                guard generation == languageRevision else { return }
                status = "Text recognition setup failed. Reopen the app to retry: \(error.localizedDescription)"
                return
            }
        } else { recognitionReady = true }
        switch state {
        case .installed: pairInstalled = true; status = "Languages installed · ready for on-device translation."
        case .supported: status = "Download the language models before starting."
        case .unsupported: status = "Apple does not support this language pair."
        @unknown default: status = "Language availability could not be determined."
        }
    }
    func prepare() {
        preparing = true
        configuration = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target), preferredStrategy: .lowLatency)
        configuration?.invalidate()
    }
    func prepare(using session: TranslationSession) async {
        let generation = languageRevision
        do {
            try await session.prepareTranslation()
            guard generation == languageRevision else { return }
            let shouldStart = startAfterDownload; startAfterDownload = false
            preparing = false
            let expectedStopRevision = stopRevision + 1 // checkPair stops the old session once.
            await checkPair()
            guard languageRevision == generation + 1, stopRevision == expectedStopRevision else { return }
            if shouldStart && pairInstalled { start() }
        } catch {
            guard generation == languageRevision else { return }
            startAfterDownload = false
            preparing = false; status = "Language setup: \(error.localizedDescription)"
        }
    }
    func checkScreenAccess() -> Bool {
        screenAuthorized = CGPreflightScreenCaptureAccess()
        if !screenAuthorized {
            status = "Screen Recording is not active for this app. Enable it in System Settings, then quit and reopen Kotoba Overlay."
        }
        return screenAuthorized
    }
    func requestScreenAccess() {
        guard !checkScreenAccess() else { return }
        if !requestedScreenAccess {
            requestedScreenAccess = true
            _ = CGRequestScreenCaptureAccess()
        }
        _ = checkScreenAccess()
    }
    func openScreenSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
    func refreshWindows() async {
        guard checkScreenAccess() else { return }
        do { windows = try await capture.choices(); status = "Choose a window to translate." }
        catch { status = "Screen access needed: \(error.localizedDescription)" }
    }
    func useWindow() { guard !videoMode else { status = "Use Select Video to exclude the webpage."; return }; stop(); areaFrame.hide(); areaScreen = nil; areaRect = nil; editingArea = false; resumeAfterAreaEdit = false; selection = windows.first { $0.id == selectedWindow }; status = selection == nil ? "Select a window first." : "Window selected. Ready to start." }
    func selectRegion() {
        selectedWindow = ""
        guard checkScreenAccess() else { return }
        stop()
        selector.select { [weak self] screen, rect in
            Task { @MainActor in
                guard let self else { return }
                do {
                    self.selection = try await (self.videoMode ? self.capture.videoChoice(screen: screen, rect: rect) : self.capture.regionChoice(screen: screen, rect: rect))
                    self.areaScreen = screen; self.areaRect = rect
                    self.updateScreenAreaCrop()
                    self.editingArea = false; self.resumeAfterAreaEdit = false; self.areaFrameVisible = true
                    if self.videoMode { self.areaFrame.hide() } else { self.updateAreaFrame() }
                    self.status = self.videoMode ? "Video selected. Enable visible captions in the player, hide its controls, then start." : "Area selected. Drag Move or any edge to adjust it anytime."
                }
                catch { self.status = "Screen access needed: \(error.localizedDescription)" }
            }
        }
    }
    var hasDrawnArea: Bool { areaScreen != nil && areaRect != nil && selection?.display != nil }
    func updateAreaFrame() {
        guard let screen = areaScreen, let rect = areaRect, areaFrameVisible else { areaFrame.hide(); return }
        areaFrame.show(screen: screen, rect: rect, began: { [weak self] in self?.beginAreaDrag() }, ended: { [weak self] in self?.endAreaDrag() }) { [weak self] rect in
            guard let self else { return }
            self.areaRect = rect
            if let old = self.selection {
                self.selection = CaptureChoice(id: old.id, name: "Screen area · \(Int(rect.width)) × \(Int(rect.height))", window: nil, display: old.display, crop: captureCrop(videoCaptureRect(rect, subtitlesOnly: self.videoMode && self.subtitlesOnly), screenHeight: screen.frame.height))
            }
        }
    }
    func toggleAreaFrame() {
        if editingArea { toggleAreaEditing() }
        areaFrameVisible.toggle(); updateAreaFrame()
    }
    func beginAreaDrag() {
        resumeAfterAreaEdit = running
        stop()
        status = "Adjusting detection area…"
    }
    func endAreaDrag() {
        let resume = resumeAfterAreaEdit; resumeAfterAreaEdit = false
        if resume { start() } else { status = "Area updated. Drag Move or any edge to adjust again." }
    }
    func toggleAreaEditing() { areaFrameVisible = true; updateAreaFrame() }
    func toggleOverlay() { overlayVisible.toggle(); if overlayVisible { overlay.show(model: self) } else { overlay.hide() } }
    func stop() {
        lineRetry = OCRRetryState()
        startAfterDownload = false
        retryTranslationAfter = .distantPast
        stopRevision += 1
        running = false; revision += 1; loop?.cancel(); loop = nil
        translationTask?.cancel(); translationTask = nil; session?.cancel(); session = nil
        original = ""; translated = ""; positionedTranslations = []; latestLines = []; overlay.hide()
    }
    func start() {
        guard !showAudio else { status = "Use the Audio subtitles panel while it is open."; return }
        if editingArea { editingArea = false; resumeAfterAreaEdit = false; updateAreaFrame() }
        guard checkScreenAccess() else { return }
        guard let selection, recognitionReady, let ocrLanguage = ocrCode(for: source) else { status = "Select a capture source and prepare the languages first."; return }
        if !pairInstalled { startAfterDownload = true; prepare(); return }
        stop(); capture.reset(); running = true; overlayVisible = true; overlay.show(model: self)
        session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target), preferredStrategy: .lowLatency)
        status = "Watching for subtitles…"
        loop = Task { [weak self] in
            var stableReading = StableOCRReading()
            var inputFields: [CGRect] = []
            var lastFieldScan = Date.distantPast
            var recognitionFailures = 0
            var transitionFailures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let activeChoice = try await self.capture.trackedVideoChoice(selection, subtitlesOnly: self.subtitlesOnly)
                    if let window = activeChoice.window {
                        guard let frame = self.capture.windowFrame(window) else { throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "The selected window has closed. Select another window."]) }
                        let top = NSScreen.screens.first?.frame.maxY ?? 0
                        let crop = activeChoice.crop ?? CGRect(origin: .zero, size: frame.size)
                        self.translationFrame = CGRect(x: frame.minX + crop.minX, y: top - frame.minY - crop.maxY, width: crop.width, height: crop.height)
                    } else if let screen = self.areaScreen, let rect = self.effectiveAreaRect {
                        self.translationFrame = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                    }
                    let image = try await self.capture.image(for: activeChoice)
                    transitionFailures = 0
                    try Task.checkCancellation()
                    let rawReading: OCRReading
                    do {
                        rawReading = try await CaptureService.recognize(image, language: ocrLanguage)
                        try Task.checkCancellation()
                        if recognitionFailures > 0 { self.status = "Text recognition recovered · watching for subtitles…" }
                        recognitionFailures = 0
                    } catch is CancellationError { return }
                    catch {
                        try Task.checkCancellation()
                        recognitionFailures = min(recognitionFailures + 1, 8)
                        // A failed frame is not evidence that the source text is unchanged.
                        self.latestLines = []
                        self.positionedTranslations = []
                        self.overlay.hide()
                        stableReading = StableOCRReading()
                        self.status = recognitionFailures < 3
                            ? "Could not read this frame · retrying…"
                            : "Text recognition is retrying. Try a smaller visible subtitle area if this continues."
                        try await Task.sleep(for: .milliseconds(250 * recognitionFailures))
                        continue
                    }
                    self.inputDetectionAuthorized = inputFieldDetectionAvailable()
                    if !self.videoMode && self.excludeInputFields && self.inputDetectionAuthorized, let frame = self.translationFrame {
                        if Date().timeIntervalSince(lastFieldScan) >= 0.75 {
                            let ids: [pid_t]
                            if let pid = selection.window?.owningApplication?.processID { ids = [pid] }
                            else {
                                let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                                ids = apps.sorted { $0.processIdentifier == front && $1.processIdentifier != front }.map(\.processIdentifier)
                            }
                            inputFields = await InputFieldDetector.scan(processIDs: ids, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0, captureFrame: frame)
                            lastFieldScan = Date()
                        }
                    } else { inputFields = []; lastFieldScan = .distantPast }
                    let reading = OCRReading(lines: excludingInputFields(rawReading.lines, captureFrame: self.translationFrame ?? .zero, fields: inputFields))
                    try Task.checkCancellation()
                    _ = stableReading.update(reading)
                    // Apply field exclusion again so retained stable text cannot reveal an input field.
                    self.latestLines = excludingInputFields(stableReading.lines, captureFrame: self.translationFrame ?? .zero, fields: inputFields)
                    self.translate(OCRReading(lines: self.latestLines).text)
                    self.refreshPositionedTranslations()
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled else { return }
                    if selection.videoRegion != nil && transitionFailures < 10 {
                        transitionFailures += 1
                        self.positionedTranslations = []; self.overlay.hide()
                        self.status = "Waiting for the player window to finish changing…"
                        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                        continue
                    }
                    self.stop(); self.status = "Capture stopped: \(error.localizedDescription)"; return
                }
            }
        }
    }
    private func refreshOverlayAppearance() {
        if overlayVisible { overlay.show(model: self) }
    }
    func exportTranslations() {
        guard historyCount > 0 else { status = "No translations to export yet."; return }
        let text = history.plainText
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Kotoba-Translations.txt"
        panel.title = "Export Session Translations"
        panel.message = "Includes original and translated text. Repeated identical translations appear once."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8); self?.status = "Translations exported to \(url.lastPathComponent)." }
            catch { self?.status = "Export failed: \(error.localizedDescription)" }
        }
    }
    private func refreshPositionedTranslations() {
        positionedTranslations = latestLines.enumerated().compactMap { index, line in
            guard let text = cache[line.text] else { return nil }
            return PositionedTranslation(id: index, text: showOriginal ? line.text + "\n" + text : text, rect: line.rect)
        }
        if overlayVisible { overlay.show(model: self) }
    }
    private func translate(_ text: String) {
        original = text
        guard translationTask == nil, Date() >= retryTranslationAfter else { return }
        let current = revision
        guard !text.isEmpty, let session else { positionedTranslations = []; overlay.hide(); status = "Watching for subtitles…"; return }
        let missing = Array(Set(latestLines.map(\.text).filter { cache[$0] == nil })).sorted()
        guard !missing.isEmpty else { refreshPositionedTranslations(); status = "Live · on device"; return }
        let sourceCode = source, targetCode = target
        status = "Translating…"
        translationTask = Task { [weak self] in
            defer {
                if let self, self.revision == current { self.translationTask = nil }
            }
            guard let self else { return }
            self.lineRetry.begin(visible: Set(self.latestLines.map(\.text)))
            for line in missing {
                guard !Task.isCancelled, self.revision == current, self.running else { return }
                if !self.lineRetry.canAttempt(line, now: Date()) { continue }
                do {
                    let response = try await session.translate(line)
                    let translated = try validatedSubtitleTranslation(response.targetText)
                    guard !Task.isCancelled, self.revision == current, self.running else { return }
                    self.cache.insert(translated, for: line, protecting: Set(self.latestLines.map(\.text)))
                    self.history.append(source: sourceCode, target: targetCode, original: line, translated: translated)
                    self.historyCount = self.history.records.count
                    self.lineRetry.succeed(line)
                    self.refreshPositionedTranslations()
                } catch {
                    guard !Task.isCancelled, self.revision == current else { return }
                    self.lineRetry.fail(line, message: error.localizedDescription, now: Date())
                }
            }
            guard self.revision == current else { return }
            self.retryTranslationAfter = Date().addingTimeInterval(self.lineRetry.passDelay)
            self.status = self.lineRetry.lastError.map { "Some text could not be translated: " + $0 } ?? "Live · on device"
        }
    }
}
