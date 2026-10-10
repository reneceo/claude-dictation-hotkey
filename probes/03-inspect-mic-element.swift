import Cocoa
import ApplicationServices

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    ($0.bundleIdentifier ?? "") == "com.anthropic.claudefordesktop" }) else { print("not found"); exit(1) }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 2.0)

func str(_ el: AXUIElement, _ a: String) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success else { return "" }
    return (v as? String) ?? ""
}
func children(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
          let a = v as? [AXUIElement] else { return [] }
    return a
}

var found: AXUIElement?
var n = 0
func walk(_ el: AXUIElement, _ d: Int) {
    if d > 32 || n > 120000 || found != nil { return }
    n += 1
    if str(el, kAXDescriptionAttribute as String).lowercased().contains("press and hold to record") { found = el; return }
    for c in children(el) { walk(c, d+1) }
}
walk(axApp, 0)

guard let el = found else { print("MIC ELEMENT NOT FOUND"); exit(1) }
print("FOUND mic element after scanning \(n) nodes")
print("  role: \(str(el, kAXRoleAttribute as String))")
print("  desc: \(str(el, kAXDescriptionAttribute as String))")

var acts: CFArray?
if AXUIElementCopyActionNames(el, &acts) == .success, let a = acts as? [String] {
    print("  ACTIONS: \(a.isEmpty ? "(none)" : a.joined(separator: ", "))")
} else { print("  ACTIONS: <could not read>") }

var pv: CFTypeRef?; var sv: CFTypeRef?
var pt = CGPoint.zero; var sz = CGSize.zero
if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success {
    AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
}
if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success {
    AXValueGetValue(sv as! AXValue, .cgSize, &sz)
}
print("  frame: origin=(\(pt.x), \(pt.y)) size=(\(sz.width) x \(sz.height))  center=(\(pt.x + sz.width/2), \(pt.y + sz.height/2))")

// also inspect children of the mic group, in case the real control is nested
for (i, c) in children(el).enumerated() {
    var ca: CFArray?
    let names = (AXUIElementCopyActionNames(c, &ca) == .success ? (ca as? [String] ?? []) : [])
    print("  child[\(i)] role=\(str(c, kAXRoleAttribute as String)) desc='\(str(c, kAXDescriptionAttribute as String))' actions=\(names)")
}
