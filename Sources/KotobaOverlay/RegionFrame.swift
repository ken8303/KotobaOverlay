import AppKit

func captureCrop(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
}

enum RegionGrip: CaseIterable { case move, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
func adjustedRegion(_ original: CGRect, dx: CGFloat, dy: CGFloat, grip: RegionGrip, bounds: CGRect) -> CGRect {
    var r = original
    if grip == .move {
        r.origin.x = min(max(r.minX + dx, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY + dy, bounds.minY), bounds.maxY - r.height)
        return r
    }
    if [.left, .topLeft, .bottomLeft].contains(grip) { let x = max(bounds.minX, min(original.minX + dx, original.maxX - 40)); r.origin.x = x; r.size.width = original.maxX - x }
    if [.right, .topRight, .bottomRight].contains(grip) { r.size.width = max(40, min(original.width + dx, bounds.maxX - original.minX)) }
    if [.bottom, .bottomLeft, .bottomRight].contains(grip) { let y = max(bounds.minY, min(original.minY + dy, original.maxY - 40)); r.origin.y = y; r.size.height = original.maxY - y }
    if [.top, .topLeft, .topRight].contains(grip) { r.size.height = max(40, min(original.height + dy, bounds.maxY - original.minY)) }
    return r
}

@MainActor final class RegionFrameController {
    private var framePanel: NSPanel?
    private var grips: [(RegionGrip, NSPanel)] = []
    private var screenBounds = CGRect.zero
    private var changed: ((CGRect) -> Void)?
    private var began: (() -> Void)?
    private var ended: (() -> Void)?
    func show(screen: NSScreen, rect: CGRect, began: @escaping () -> Void, ended: @escaping () -> Void, changed: @escaping (CGRect) -> Void) {
        if framePanel == nil {
            let panel = makePanel()
            panel.ignoresMouseEvents = true
            panel.contentView = RegionOutlineView()
            framePanel = panel
            for grip in RegionGrip.allCases {
                let p = makePanel()
                let view = RegionGripView()
                view.grip = grip
                view.begin = { [weak self] in self?.began?(); return self?.framePanel?.frame ?? .zero }
                view.drag = { [weak self] initial, dx, dy in
                    guard let self else { return }
                    let result = adjustedRegion(initial, dx: dx, dy: dy, grip: grip, bounds: self.screenBounds)
                    self.layout(result)
                    self.changed?(result)
                }
                view.end = { [weak self] in self?.ended?() }
                p.contentView = view
                grips.append((grip, p))
            }
        }
        screenBounds = screen.frame; self.began = began; self.ended = ended
        self.changed = { global in changed(global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)) }
        layout(rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
        framePanel?.orderFrontRegardless()
        grips.forEach { $0.1.orderFrontRegardless() }
    }
    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Capture Area"
        p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false; p.hidesOnDeactivate = false
        return p
    }
    private func layout(_ r: CGRect) {
        framePanel?.setFrame(r, display: true)
        for (grip, p) in grips {
            let box: CGRect
            switch grip {
            case .move: box = CGRect(x: r.midX - 30, y: r.maxY - 24, width: 60, height: 20)
            case .left: box = CGRect(x: r.minX, y: r.minY + 10, width: 8, height: max(1, r.height - 20))
            case .right: box = CGRect(x: r.maxX - 8, y: r.minY + 10, width: 8, height: max(1, r.height - 20))
            case .top: box = CGRect(x: r.minX + 10, y: r.maxY - 8, width: max(1, r.width - 20), height: 8)
            case .bottom: box = CGRect(x: r.minX + 10, y: r.minY, width: max(1, r.width - 20), height: 8)
            case .topLeft: box = CGRect(x: r.minX, y: r.maxY - 10, width: 10, height: 10)
            case .topRight: box = CGRect(x: r.maxX - 10, y: r.maxY - 10, width: 10, height: 10)
            case .bottomLeft: box = CGRect(x: r.minX, y: r.minY, width: 10, height: 10)
            case .bottomRight: box = CGRect(x: r.maxX - 10, y: r.minY, width: 10, height: 10)
            }
            p.setFrame(box, display: true)
        }
    }
    func hide() { framePanel?.orderOut(nil); grips.forEach { $0.1.orderOut(nil) } }
}
final class RegionOutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemMint.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); path.lineWidth = 2; path.stroke()
    }
}
final class RegionGripView: NSView {
    var grip = RegionGrip.move
    var begin: (() -> CGRect)?
    var drag: ((CGRect, CGFloat, CGFloat) -> Void)?
    var end: (() -> Void)?
    private var initial = CGRect.zero
    private var start = CGPoint.zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemMint.withAlphaComponent(grip == .move ? 0.95 : 0.35).setFill(); bounds.fill()
        if grip == .move { ("Move" as NSString).draw(at: CGPoint(x: 13, y: 3), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.black]) }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = window.convertPoint(toScreen: event.locationInWindow)
        initial = begin?() ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        drag?(initial, point.x - start.x, point.y - start.y)
    }
    override func mouseUp(with event: NSEvent) { end?() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: grip == .move ? .openHand : ([RegionGrip.left, .right].contains(grip) ? .resizeLeftRight : .resizeUpDown))
    }
}
