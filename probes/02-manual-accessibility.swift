import Cocoa
import ApplicationServices

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    ($0.bundleIdentifier ?? "") == "com.anthropic.claudefordesktop" }) else { print("not found"); exit(1) }
let axApp = AXUIElementCreateApplication(app.processIdentifier)

// Chromium/Electron gate: enables web-content a11y on demand.
let r1 = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
let r2 = AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
print("AXManualAccessibility set -> \(r1.rawValue)   AXEnhancedUserInterface set -> \(r2.rawValue)")
Thread.sleep(forTimeInterval: 2.5)

func str(_ el: AXUIElement, _ a: String) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success else { return "" }
    if let s = v as? String { return s }
    return ""
}
func children(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
          let a = v as? [AXUIElement] else { return [] }
    return a
}

var n = 0
var hits: [String] = []
var roles: [String: Int] = [:]
let needles = ["mic", "dictat", "voice", "record", "speak"]

func walk(_ el: AXUIElement, _ d: Int, _ p: String) {
    if d > 30 || n > 120000 { return }
    n += 1
    let role = str(el, kAXRoleAttribute as String)
    roles[role, default: 0] += 1
    let t = str(el, kAXTitleAttribute as String)
    let desc = str(el, kAXDescriptionAttribute as String)
    let help = str(el, kAXHelpAttribute as String)
    let id = str(el, "AXIdentifier")
    let blob = "\(role) \(t) \(desc) \(help) \(id)".lowercased()
    if needles.contains(where: { blob.contains($0) }) {
        hits.append("d\(d) \(p) | role=\(role) title='\(t)' desc='\(desc)' help='\(help)' id='\(id)'")
    }
    for (i, c) in children(el).enumerated() { walk(c, d+1, "\(p)/\(role)[\(i)]") }
}
walk(axApp, 0, "")
print("nodes visited: \(n)")
print("--- role histogram (top 15) ---")
for (r, c) in roles.sorted(by: { $0.value > $1.value }).prefix(15) { print("  \(c)\t\(r)") }
print("=== MATCHES (\(hits.count)) ===")
for h in hits.prefix(40) { print(h) }
