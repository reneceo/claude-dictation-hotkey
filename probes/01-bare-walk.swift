import Cocoa
import ApplicationServices

// Read-only accessibility-tree probe. Inspects only; never presses anything.

let trusted = AXIsProcessTrusted()
FileHandle.standardError.write("AXIsProcessTrusted: \(trusted)\n".data(using: .utf8)!)

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    ($0.localizedName ?? "") == "Claude" || ($0.bundleIdentifier ?? "").contains("claude")
}) else {
    print("NO CLAUDE PROCESS FOUND")
    exit(1)
}
print("app: \(app.localizedName ?? "?")  bundle: \(app.bundleIdentifier ?? "?")  pid: \(app.processIdentifier)")

let axApp = AXUIElementCreateApplication(app.processIdentifier)

func str(_ el: AXUIElement, _ attr: String) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

var nodeCount = 0
var hits: [String] = []
let needles = ["mic", "dictat", "voice", "record", "speak", "audio"]

func walk(_ el: AXUIElement, depth: Int, path: String) {
    if depth > 22 || nodeCount > 40000 { return }
    nodeCount += 1
    let role = str(el, kAXRoleAttribute as String)
    let sub  = str(el, kAXSubroleAttribute as String)
    let title = str(el, kAXTitleAttribute as String)
    let desc = str(el, kAXDescriptionAttribute as String)
    let help = str(el, kAXHelpAttribute as String)
    let ident = str(el, "AXIdentifier")
    let value = str(el, kAXValueAttribute as String)

    let blob = "\(role) \(sub) \(title) \(desc) \(help) \(ident) \(value)".lowercased()
    if needles.contains(where: { blob.contains($0) }) {
        hits.append("d\(depth) \(path) | role=\(role) sub=\(sub) title='\(title)' desc='\(desc)' help='\(help)' id='\(ident)' val='\(value.prefix(40))'")
    }
    for (i, c) in children(el).enumerated() {
        walk(c, depth: depth + 1, path: "\(path)/\(role)[\(i)]")
    }
}

walk(axApp, depth: 0, path: "")
print("nodes visited: \(nodeCount)")
print("=== MIC/VOICE MATCHES (\(hits.count)) ===")
for h in hits.prefix(60) { print(h) }
