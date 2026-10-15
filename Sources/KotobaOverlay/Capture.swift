import AppKit
import ScreenCaptureKit
import Vision

struct CaptureChoice: Identifiable {
    let id: String
    let name: String
    let window: SCWindow?
    let display: SCDisplay?
    var crop: CGRect?
    var videoRegion: CGRect? = nil
}

struct OCRLine: Sendable { let text: String; let rect: CGRect; let confidence: Float }
struct OCRReading: Sendable {
    let lines: [OCRLine]
    var text: String { lines.map(\.text).joined(separator: "\n") }
    var confidence: Float { lines.map(\.confidence).min() ?? 0 }
}
@MainActor final class CaptureService {
    private var filters: [String: SCContentFilter] = [:]
    func reset() { filters.removeAll(); fullscreenWindow = nil; lastVideoRefresh = .distantPast }
    func choices() async throws -> [CaptureChoice] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width > 150 && $0.frame.height > 80 }.map {
            CaptureChoice(id: "w\($0.windowID)", name: "\($0.owningApplication?.applicationName ?? "App") — \($0.title ?? "Untitled window")", window: $0, display: nil)
        }.sorted { $0.name < $1.name }
    }
    func regionChoice(screen: NSScreen, rect: CGRect) async throws -> CaptureChoice {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected display is no longer available."]) }
        return CaptureChoice(id: "d\(display.displayID)", name: "Screen area · \(Int(rect.width)) × \(Int(rect.height))", window: nil, display: display, crop: captureCrop(rect, screenHeight: screen.frame.height))
    }
    func videoChoice(screen: NSScreen, rect: CGRect) async throws -> CaptureChoice {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let picked = CGRect(x: global.minX, y: top - global.maxY, width: global.width, height: global.height)
        let order = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? UInt32 }
        let candidates = content.windows.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 &&
            $0.frame.intersection(picked).width * $0.frame.intersection(picked).height >= picked.width * picked.height * 0.9
        }.sorted { (order.firstIndex(of: $0.windowID) ?? Int.max) < (order.firstIndex(of: $1.windowID) ?? Int.max) }
        guard let window = candidates.first else {
            throw NSError(domain: "Video", code: 1, userInfo: [NSLocalizedDescriptionKey: "No player window found. Draw inside one visible player window."])
        }
        let region = CGRect(x: (picked.minX - window.frame.minX) / window.frame.width,
                            y: (picked.minY - window.frame.minY) / window.frame.height,
                            width: picked.width / window.frame.width, height: picked.height / window.frame.height)
        return CaptureChoice(id: "w\(window.windowID)", name: "Video · \(window.owningApplication?.applicationName ?? "Player")", window: window, display: nil, crop: nil, videoRegion: region)
    }
    private var lastVideoRefresh = Date.distantPast
    private var fullscreenWindow: SCWindow?
    func trackedVideoChoice(_ original: CaptureChoice, subtitlesOnly: Bool) async throws -> CaptureChoice {
        guard let originalWindow = original.window, let region = original.videoRegion else { return original }
        if Date().timeIntervalSince(lastVideoRefresh) > 1 {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            fullscreenWindow = content.windows.first { candidate in
                candidate.isOnScreen && candidate.windowLayer == 0 &&
                (candidate.windowID == originalWindow.windowID || !content.windows.contains { $0.windowID == originalWindow.windowID && $0.isOnScreen }) &&
                candidate.owningApplication?.processID == originalWindow.owningApplication?.processID &&
                content.displays.contains { isFullscreenVideoWindow(candidate.frame, display: $0.frame) }
            }
            lastVideoRefresh = Date()
        }
        let window = fullscreenWindow ?? originalWindow
        guard let frame = windowFrame(window) else { throw NSError(domain: "Video", code: 2, userInfo: [NSLocalizedDescriptionKey: "Player window closed. Select the video again."]) }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let fullscreen = NSScreen.screens.contains {
            isFullscreenVideoWindow(frame, display: CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height))
        }
        let crop = trackedVideoCrop(region: region, windowSize: frame.size, fullscreen: fullscreen, subtitlesOnly: subtitlesOnly)
        return CaptureChoice(id: "w\(window.windowID)", name: original.name, window: window, display: nil, crop: crop, videoRegion: region)
    }
    func windowFrame(_ window: SCWindow) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], window.windowID) as? [[String: Any]],
              let info = list.first, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return rect
    }
    func image(for choice: CaptureChoice) async throws -> CGImage {
        let filter: SCContentFilter
        if let cached = filters[choice.id] { filter = cached }
        else if let window = choice.window { filter = SCContentFilter(desktopIndependentWindow: window) }
        else if let display = choice.display {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        } else { throw CancellationError() }
        filters[choice.id] = filter
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        let size = choice.crop?.size ?? choice.window.flatMap { windowFrame($0)?.size } ?? filter.contentRect.size
        if let crop = choice.crop { config.sourceRect = crop }
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    // Retry rejected capture images using a conventional, opaque sRGB bitmap.
    nonisolated static func recognitionBitmap(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw NSError(domain: "OCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not prepare the captured frame for text recognition."])
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bitmap = context.makeImage() else {
            throw NSError(domain: "OCR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the text-recognition image."])
        }
        return bitmap
    }
    nonisolated static func recognize(_ image: CGImage, language: String) async throws -> OCRReading {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [language]
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool {
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                try Task.checkCancellation()
                let bitmap = try recognitionBitmap(image)
                try VNImageRequestHandler(cgImage: bitmap).perform([request])
            }
            try Task.checkCancellation()
            let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first else { return nil }
                return OCRLine(text: text.string, rect: observation.boundingBox, confidence: text.confidence)
            }.sorted { $0.rect.midY > $1.rect.midY }
            return OCRReading(lines: lines)
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
            request.cancel()
        }
    }
}
