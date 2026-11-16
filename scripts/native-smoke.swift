import AppKit
import ApplicationServices
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "NativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func tree(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 16 else { return [] }
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.flatMap { tree($0, depth: depth + 1) }
}
func named(_ root: AXUIElement, _ name: String) -> AXUIElement? {
    tree(root).first { element in
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains {
            (attribute(element, $0) as? String) == name
        }
    }
}
func press(_ root: AXUIElement, _ name: String) throws {
    guard let element = named(root, name) else { throw NSError(domain: "NativeSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing control: \(name)"]) }
    try require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "Could not press \(name)")
}
func waitFor(_ root: AXUIElement, _ name: String, timeout: TimeInterval = 6) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if named(root, name) != nil { return }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw NSError(domain: "NativeSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "Visible outcome missing: \(name)"])
}


func bounds(_ element: AXUIElement) throws -> CGRect {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute) else {
        throw NSError(domain: "NativeSmoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing native bounds"])
    }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    try require(AXValueGetValue(position as! AXValue, .cgPoint, &point), "Position unavailable")
    try require(AXValueGetValue(size as! AXValue, .cgSize, &dimensions), "Size unavailable")
    return CGRect(origin: point, size: dimensions)
}
func mouse(_ type: CGEventType, at point: CGPoint) throws {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        throw NSError(domain: "NativeSmoke", code: 6, userInfo: [NSLocalizedDescriptionKey: "Mouse event unavailable"])
    }
    event.post(tap: .cghidEventTap)
}

func drag(from start: CGPoint, through points: [CGPoint]) async throws {
    try mouse(.leftMouseDown, at: start)
    for point in points {
        try await Task.sleep(nanoseconds: 40_000_000)
        try mouse(.leftMouseDragged, at: point)
    }
    try mouse(.leftMouseUp, at: points.last ?? start)
}


func appWindow(_ root: AXUIElement, title: String) -> AXUIElement? {
    (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first {
        (attribute($0, kAXTitleAttribute) as? String) == title
    }
}
@MainActor func waitForExit(_ app: NSRunningApplication) async throws {
    let deadline = Date().addingTimeInterval(4)
    while !app.isTerminated && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
    try require(app.isTerminated, "Owned test app did not quit")
}
@main struct NativeSmoke {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        try require(AXIsProcessTrusted(), "Accessibility access unavailable; do not alter permissions")
        let args = CommandLine.arguments
        try require(args.count == 4, "Expected isolated app, data directory and screenshot")
        let bundle = URL(fileURLWithPath: args[1])
        let data = URL(fileURLWithPath: args[2])
        try require(data.lastPathComponent.hasPrefix("qa-native-"), "Isolated data directory required")
        try require(bundle.deletingLastPathComponent() == data, "App must be the isolated QA copy")
        try require(Bundle(url: bundle)?.bundleIdentifier?.hasPrefix("local.pomodoro.qa.") == true, "Isolated identity required")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--data-dir", data.path]
        var app = try await NSWorkspace.shared.openApplication(at: bundle, configuration: config)
        defer { app.terminate() }
        var root = AXUIElementCreateApplication(app.processIdentifier)
        let title = "POMODORO Timer"
        try await waitFor(root, "Visual timer, 25:00 remaining in Focus")
        guard let window = appWindow(root, title: title),
              let dial = named(root, "Visual timer, 25:00 remaining in Focus") else { throw NSError(domain: "Missing window/dial", code: 1) }
        app.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        try await Task.sleep(nanoseconds: 300_000_000)
        let frame = try bounds(dial)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let radius = frame.width * 0.38
        let points = (1...8).map { i in
            CGPoint(x: center.x + sin(Double(i) / 8 * .pi / 2) * radius,
                    y: center.y - cos(Double(i) / 8 * .pi / 2) * radius)
        }
        try await drag(from: CGPoint(x: center.x, y: center.y - radius), through: points)
        try await waitFor(root, "Visual timer, 15:00 remaining in Focus")
        let stateFile = data.appendingPathComponent("state.json")
        func saved() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile)) as! [String: Any] }
        var state = try saved()
        try require((state["timer"] as? [String: Any])?["remaining"] as? Double == 900, "Dial did not persist 15 minutes")
        for name in ["Timer sound", "Timer blink"] { try press(root, name) }
        state = try saved()
        try require(state["timerSoundEnabled"] as? Bool == true && state["timerBlinkEnabled"] as? Bool == true, "Alert controls did not persist")
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let id = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowName as String] as? String) == title })?[kCGWindowNumber as String] as? UInt32 else { throw NSError(domain: "Capture", code: 1) }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(id), args[3]]
        try capture.run(); capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "Screenshot failed")
        try press(root, "Start timer")
        try await waitFor(root, "Pause timer")
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try press(root, "Pause timer")
        state = try saved()
        let paused = state["timer"] as! [String: Any]
        try require(paused["deadline"] == nil && (paused["remaining"] as? Double ?? 900) < 900, "Pause did not save elapsed time")
        let before = try bounds(window)
        try await drag(from: CGPoint(x: before.maxX - 35, y: before.minY + 10), through: [CGPoint(x: before.maxX + 15, y: before.minY + 45)])
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try bounds(window)
        try require(abs(after.minX - before.minX) > 20 || abs(after.minY - before.minY) > 20, "Upper frame did not drag")
        guard let close = attribute(window, kAXCloseButtonAttribute) else { throw NSError(domain: "Close", code: 1) }
        try require(AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success, "Close failed")
        try await Task.sleep(nanoseconds: 200_000_000)
        try require(!app.isTerminated && appWindow(root, title: title) == nil, "Close did not leave menu bar app running")
        app.terminate(); try await waitForExit(app)
        app = try await NSWorkspace.shared.openApplication(at: bundle, configuration: config)
        root = AXUIElementCreateApplication(app.processIdentifier)
        try await waitFor(root, "Start timer")
        state = try saved()
        try require(state["timer"] as? NSDictionary == paused as NSDictionary, "Relaunch changed paused timer")
        try press(root, "Reset timer")
        try await waitFor(root, "Visual timer, 15:00 remaining in Focus")
        app.terminate(); try await waitForExit(app)
        state = try saved()
        state["timer"] = ["phase": "Focus", "remaining": 2, "deadline": Date().addingTimeInterval(3).timeIntervalSinceReferenceDate]
        try JSONSerialization.data(withJSONObject: state).write(to: stateFile)
        app = try await NSWorkspace.shared.openApplication(at: bundle, configuration: config)
        root = AXUIElementCreateApplication(app.processIdentifier)
        try await waitFor(root, "Visual timer, 05:00 remaining in Break")
        state = try saved()
        try require((state["timer"] as? [String: Any])?["phase"] as? String == "Break", "Completion did not persist break")
        print("PASS: native dial drag to 15 minutes, sound/blink toggles, start/pause, upper-frame drag, close, relaunch, reset and completion; screenshot captured")
    }
}
