import AppKit
import ApplicationServices

func excludingInputFields(_ lines: [OCRLine], captureFrame: CGRect, fields: [CGRect]) -> [OCRLine] {
    lines.filter { line in
        let box = textBox(line.rect, in: captureFrame.size).offsetBy(dx: captureFrame.minX, dy: captureFrame.minY)
        return !fields.contains { $0.intersects(box) }
    }
}

#if APP_STORE
func inputFieldDetectionAvailable() -> Bool { false }
enum InputFieldDetector {
    static func scan(processIDs: [pid_t], desktopTop: CGFloat, captureFrame: CGRect) async -> [CGRect] { [] }
}
#else
func inputFieldDetectionAvailable() -> Bool { AXIsProcessTrusted() }
/// Uses existing Accessibility authorization only. Reads roles and bounds, not field contents.
enum InputFieldDetector {
    static func scan(processIDs: [pid_t], desktopTop: CGFloat, captureFrame: CGRect) async -> [CGRect] {
        await Task.detached(priority: .utility) {
            guard AXIsProcessTrusted() else { return [] }
            var fields: [CGRect] = []
            var budget = 1000
            let deadline = Date().addingTimeInterval(0.25)
            func get(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
                return value
            }
            func frame(_ element: AXUIElement) -> CGRect? {
                guard let p = get(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
                      let s = get(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
                var point = CGPoint.zero; var size = CGSize.zero
                guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
                return CGRect(x: point.x, y: desktopTop - point.y - size.height, width: size.width, height: size.height)
            }
            func visit(_ element: AXUIElement, depth: Int) {
                guard budget > 0, depth < 30, Date() < deadline else { return }
                budget -= 1
                let role = get(element, kAXRoleAttribute) as? String ?? ""
                if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || get(element, "AXEditable") as? Bool == true {
                    if let rect = frame(element), rect.intersects(captureFrame) { fields.append(rect.insetBy(dx: -3, dy: -3)) }
                    return
                }
                for child in get(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
            }
            for pid in processIDs where Date() < deadline {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.04)
                if let focused = get(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() { visit(focused as! AXUIElement, depth: 0) }
                for window in get(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    if let rect = frame(window), rect.intersects(captureFrame) { visit(window, depth: 0) }
                }
            }
            return fields
        }.value
    }
}

#endif
