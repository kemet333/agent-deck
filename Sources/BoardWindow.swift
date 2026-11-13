import AppKit
import WebKit

/// The «Agentes» window: the board's page (Resources/board, the same React board as in Diego OS, with xterm.js) in a
/// WKWebView, talking to BoardEngine through a message handler with replies, no server and no port. The page calls
/// `window.webkit.messageHandlers.board.postMessage({path, body})` and awaits the answer; the live output comes back
/// through `window.__boardEvent(event, data)`, batched every 30 ms.
final class BoardWindowController: NSObject, WKScriptMessageHandlerWithReply, NSWindowDelegate {
    let engine: BoardEngine
    private(set) var window: NSWindow!
    private var web: WKWebView!
    private var pending: [(String, String)] = []
    private var flushScheduled = false

    init(engine: BoardEngine) {
        self.engine = engine
        super.init()
        let conf = WKWebViewConfiguration()
        conf.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "board")
        web = WKWebView(frame: .zero, configuration: conf)
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = T.s("Agents", "Agentes")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.063, blue: 0.075, alpha: 1)
        window.contentView = web
        window.delegate = self
        window.setFrameAutosaveName("AgentBarBoard")
        window.center()
        engine.emit = { [weak self] ev, data in self?.queue(ev, data) }
        engine.start()
        load()
    }
    private func load() {
        let dir = ProcessInfo.processInfo.environment["AGENT_BOARD_WEB"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!.appendingPathComponent("board")
        web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let m = message.body as? [String: Any], let path = m["path"] as? String else { return replyHandler(nil, "Petición no válida.") }
        do { replyHandler(try engine.handle(path, m["body"] as? [String: Any] ?? [:]), nil) }
        catch { replyHandler(nil, error.localizedDescription) }
    }
    private func queue(_ ev: String, _ data: String) {
        pending.append((ev, data))
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.flush() }
    }
    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let batch = pending; pending = []
        guard let json = try? JSONSerialization.data(withJSONObject: batch.map { [$0.0, $0.1] }), let s = String(data: json, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__boardEvents && window.__boardEvents(\(s))", completionHandler: nil)
    }
}
