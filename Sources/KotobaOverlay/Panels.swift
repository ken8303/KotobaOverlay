import AppKit
import SwiftUI

struct PositionedTranslation: Identifiable, Equatable {
    let id: Int
    let text: String
    let rect: CGRect
}
func textBox(_ normalized: CGRect, in size: CGSize) -> CGRect {
    CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height, width: normalized.width * size.width, height: normalized.height * size.height)
}
@MainActor final class OverlayController {
    private var panel: NSPanel?
    func show(model: AppModel) {
        guard let frame = model.translationFrame, frame.width > 0, frame.height > 0 else { hide(); return }
        if panel == nil {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.hidesOnDeactivate = false; p.ignoresMouseEvents = true
            p.contentView = TranslationCanvas()
            panel = p
        }
        let padding = max(160, model.fontSize * 4)
        let expandedFrame = frame.insetBy(dx: -padding, dy: -padding)
        if panel?.frame != expandedFrame { panel?.setFrame(expandedFrame, display: true) }
        if let canvas = panel?.contentView as? TranslationCanvas {
            let sourceBounds = CGRect(origin: CGPoint(x: padding, y: padding), size: frame.size)
            let changed = canvas.items != model.positionedTranslations || canvas.fontSize != model.fontSize || canvas.opacity != model.opacity || canvas.sourceBounds != sourceBounds
            canvas.sourceBounds = sourceBounds
            canvas.items = model.positionedTranslations
            canvas.fontSize = model.fontSize; canvas.opacity = model.opacity
            if changed { canvas.needsDisplay = true }
        }
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }
    func hide() { panel?.orderOut(nil) }
}
struct TranslationLabelLayout {
    let box: CGRect
    let attributes: [NSAttributedString.Key: Any]
}

func translationLabelLayout(text: String, anchor: CGRect, bounds: CGRect, fontSize: CGFloat) -> TranslationLabelLayout {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
        .foregroundColor: NSColor.white, .paragraphStyle: paragraph
    ]
    let width = min(bounds.width, max(anchor.width + 12, fontSize * 20))
    let measured = (text as NSString).boundingRect(with: CGSize(width: max(1, width - 12), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    let height = ceil(measured.height) + 8
    let x = max(bounds.minX, min(anchor.midX - width / 2, bounds.maxX - width))
    let y = max(bounds.minY, min(anchor.midY - height / 2, bounds.maxY - height))
    return TranslationLabelLayout(box: CGRect(x: x, y: y, width: width, height: height), attributes: attributes)
}

final class TranslationCanvas: NSView {
    var items: [PositionedTranslation] = []
    var fontSize: CGFloat = 28
    var opacity: Double = 0.95
    var sourceBounds: CGRect?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let source = sourceBounds ?? bounds
        for item in items where !item.text.isEmpty {
            let anchor = textBox(item.rect, in: source.size).offsetBy(dx: source.minX, dy: source.minY)
            let layout = translationLabelLayout(text: item.text, anchor: anchor, bounds: bounds, fontSize: fontSize)
            NSColor.black.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: layout.box, xRadius: 3, yRadius: 3).fill()
            (item.text as NSString).draw(with: layout.box.insetBy(dx: 6, dy: 4), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: layout.attributes)
        }
    }
}

@MainActor final class RegionSelector {
    private var windows: [NSWindow] = []
    func select(completion: @escaping (NSScreen, CGRect) -> Void) {
        cancel()
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isReleasedWhenClosed = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.finished = { [weak self] rect in self?.cancel(); if let rect { completion(screen, rect) } }
            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
    }
    func cancel() { windows.forEach { $0.orderOut(nil) }; windows.removeAll() }
}
final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
final class SelectionView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var finished: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var box = CGRect.zero
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
        let message = "Drag around subtitles or dialogue · Escape to cancel"
        (message as NSString).draw(at: CGPoint(x: 32, y: bounds.height - 64), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white])
        NSColor.systemMint.setStroke(); let path = NSBezierPath(rect: box); path.lineWidth = 3; path.stroke()
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }; let point = convert(event.locationInWindow, from: nil)
        box = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(start.x - point.x), height: abs(start.y - point.y)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); finished?(box.width > 20 && box.height > 20 ? box : nil) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finished?(nil) } }
}
