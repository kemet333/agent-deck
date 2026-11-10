import AppKit
import SwiftUI

/// Lo que Claude Code pide hacer en un permiso (PermissionRequest): la orden, el archivo y sus cambios.
/// Se lee del archivo que deja el gancho y sirve para la tarjeta («Bash · git push») y para «Ver cambios».
struct PermissionChange: Equatable {
    struct Edit: Equatable { var old: String; var new: String; var all: Bool }
    var tool: String
    var path: String = ""
    var command: String = ""
    var edits: [Edit] = []
    /// Write: el archivo entero nuevo.
    var content: String? = nil
    /// Otras herramientas: la dirección, lo que busca o su descripción.
    var other: String = ""

    /// «mcp__github__create_pr» → «create_pr»
    var toolName: String { tool.hasPrefix("mcp__") ? String(tool.split(separator: "_").last ?? Substring(tool)) : tool }
    var file: String { path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent }
    var hasDiff: Bool { !edits.isEmpty || content != nil }
    /// Una orden larga se lee entera en la ventana.
    var longCommand: Bool { command.count > 110 || command.contains("\n") }
    var summary: String {
        let what = !command.isEmpty ? command : !file.isEmpty ? file : other
        return what.isEmpty ? toolName : "\(toolName) · \(what.prefix(400))"
    }

    static func from(_ j: [String: Any]) -> PermissionChange? {
        guard let tool = j["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = j["tool_input"] as? [String: Any] ?? [:]
        var c = PermissionChange(tool: tool)
        c.path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? ""
        c.command = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let o = input["old_string"] as? String, let n = input["new_string"] as? String {
            c.edits = [Edit(old: o, new: n, all: input["replace_all"] as? Bool ?? false)]
        } else if let list = input["edits"] as? [[String: Any]] {
            c.edits = list.compactMap { e in
                guard let o = e["old_string"] as? String, let n = e["new_string"] as? String else { return nil }
                return Edit(old: o, new: n, all: e["replace_all"] as? Bool ?? false)
            }
        } else if let w = input["content"] as? String { c.content = w }
        else if let s = input["new_source"] as? String { c.content = s }
        c.other = (input["url"] as? String) ?? (input["pattern"] as? String) ?? (input["description"] as? String)
            ?? (input["query"] as? String) ?? (input["prompt"] as? String).map { String($0.prefix(160)) } ?? ""
        return c
    }

    /// El archivo del gancho (Application Support/Agent Deck/hooks/<n>.json). No lo borra: eso lo hace quien lo pidió.
    static func read(file name: String) -> PermissionChange? {
        guard name.range(of: "^[0-9]+-[0-9]+\\.json$", options: .regularExpression) != nil else { return nil }
        let url = Autopilot.folder.appendingPathComponent("hooks").appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), data.count < 4_000_000,
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              j["hook_event_name"] as? String == "PermissionRequest" || j["tool_name"] != nil else { return nil }
        return from(j)
    }

    /// El archivo tal como está ahora (solo texto, hasta 3 MB). Las carpetas que macOS protege no se leen: pedirían permiso.
    func currentFile() -> String? {
        guard path.hasPrefix("/") else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if ["Desktop", "Documents", "Downloads"].contains(where: { path.hasPrefix(home + "/" + $0 + "/") }) { return nil }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size < 3_000_000 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
    /// El archivo con los cambios hechos, o nil si no se pueden aplicar sobre él.
    func applied(to before: String) -> String? {
        var t = before
        for e in edits {
            guard !e.old.isEmpty, let r = t.range(of: e.old) else { return nil }
            t = e.all ? t.replacingOccurrences(of: e.old, with: e.new) : t.replacingCharacters(in: r, with: e.new)
        }
        return t
    }
    func diff(file: String?? = .none) -> [LineDiff.Line] {
        let now: String? = { if case .some(let f) = file { return f }; return currentFile() }()
        if let content { return LineDiff.diff(LineDiff.lines(now ?? ""), LineDiff.lines(content)) }
        if let now, let after = applied(to: now) { return LineDiff.diff(LineDiff.lines(now), LineDiff.lines(after)) }
        // sin el archivo: cada cambio por separado
        var out: [LineDiff.Line] = []
        for (i, e) in edits.enumerated() {
            if i > 0 { out.append(LineDiff.Line(kind: .gap, text: "")) }
            out += LineDiff.diff(LineDiff.lines(e.old), LineDiff.lines(e.new), context: 1000)
        }
        return out
    }
}

/// Diferencias línea a línea, con 3 de contexto alrededor de cada cambio. Lo común del principio y del final se quita
/// antes de comparar, así un cambio en un archivo grande sale al instante.
enum LineDiff {
    enum Kind: Equatable { case same, add, del, gap }
    struct Line: Equatable, Identifiable {
        let kind: Kind
        let text: String
        var id = UUID()
        static func == (a: Line, b: Line) -> Bool { a.kind == b.kind && a.text == b.text }
    }
    static func lines(_ s: String) -> [String] { s.isEmpty ? [] : s.components(separatedBy: "\n") }

    static func diff(_ a: [String], _ b: [String], context: Int = 3) -> [Line] {
        var pre = 0
        while pre < a.count, pre < b.count, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre, suf < b.count - pre, a[a.count - 1 - suf] == b[b.count - 1 - suf] { suf += 1 }
        let am = Array(a[pre..<(a.count - suf)]), bm = Array(b[pre..<(b.count - suf)])
        var mid: [Line] = []
        let n = am.count, m = bm.count
        if n > 0, m > 0, n * m <= 1_500_000 {
            // la subsecuencia común más larga, de atrás hacia delante
            var t = [Int32](repeating: 0, count: (n + 1) * (m + 1))
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    t[i * (m + 1) + j] = am[i] == bm[j] ? t[(i + 1) * (m + 1) + j + 1] + 1 : max(t[(i + 1) * (m + 1) + j], t[i * (m + 1) + j + 1])
                }
            }
            var i = 0, j = 0
            while i < n || j < m {
                // lo que sale va antes que lo que entra, como en git
                if i < n, j < m, am[i] == bm[j] { mid.append(Line(kind: .same, text: am[i])); i += 1; j += 1 }
                else if i < n, j == m || t[(i + 1) * (m + 1) + j] >= t[i * (m + 1) + j + 1] { mid.append(Line(kind: .del, text: am[i])); i += 1 }
                else { mid.append(Line(kind: .add, text: bm[j])); j += 1 }
            }
        } else {
            mid = am.map { Line(kind: .del, text: $0) } + bm.map { Line(kind: .add, text: $0) }
        }
        let all = a[0..<pre].map { Line(kind: .same, text: $0) } + mid + a[(a.count - suf)...].map { Line(kind: .same, text: $0) }
        // lo que no cambia, plegado: solo `context` líneas alrededor de cada cambio
        var keep = [Bool](repeating: false, count: all.count)
        for (k, l) in all.enumerated() where l.kind != .same {
            for x in max(0, k - context)...min(all.count - 1, k + context) { keep[x] = true }
        }
        var out: [Line] = [], skipped = 0
        for (k, l) in all.enumerated() {
            if keep[k] {
                if skipped > 0 { out.append(Line(kind: .gap, text: T.s("\(skipped) unchanged lines", "\(skipped) líneas sin cambios"))); skipped = 0 }
                out.append(l)
            } else { skipped += 1 }
        }
        if skipped > 0 && !out.isEmpty { out.append(Line(kind: .gap, text: T.s("\(skipped) unchanged lines", "\(skipped) líneas sin cambios"))) }
        return out
    }
}

/// «Ver cambios»: una ventana aparte (no la del orbe) con lo que Claude Code quiere cambiar, y Permitir / No.
@MainActor
enum ChangesWindow {
    private static var window: NSWindow?
    static func show(_ change: PermissionChange, place: String, allow: @escaping () -> Void, deny: @escaping () -> Void) {
        window?.close()
        let lines = change.hasDiff ? change.diff() : []
        let close = { window?.close(); window = nil }
        let view = ChangesView(change: change, place: place, lines: lines,
                               allow: { close(); allow() }, deny: { close(); deny() })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = change.file.isEmpty ? change.toolName : change.file
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.contentView = NSHostingView(rootView: view)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct ChangesView: View {
    let change: PermissionChange
    let place: String
    let lines: [LineDiff.Line]
    let allow: () -> Void
    let deny: () -> Void
    private var added: Int { lines.filter { $0.kind == .add }.count }
    private var removed: Int { lines.filter { $0.kind == .del }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(change.toolName).font(.system(size: 13, weight: .semibold))
                Text(change.path.isEmpty ? place : change.path).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                if change.hasDiff {
                    Text("+\(added)").font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundColor(rgb(0x3fb950))
                    Text("−\(removed)").font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundColor(rgb(0xf85149))
                }
            }
            .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 10)
            Divider()
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    Group {
                        if change.hasDiff {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(lines) { l in row(l).frame(minWidth: geo.size.width, alignment: .leading) }
                            }.padding(.vertical, 8)
                        } else {
                            Text(change.command.isEmpty ? change.summary : change.command)
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: geo.size.width - 36, alignment: .leading).padding(18)
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text(T.s("No answer in 60 s: Claude asks you there.", "Sin respuesta en 60 s, Claude te lo pregunta allí."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(T.s("No", "No"), action: deny).keyboardShortcut(.cancelAction)
                Button(T.s("Allow", "Permitir"), action: allow).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(rgb(0xff5b1f))
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(minWidth: 520, minHeight: 320)
    }

    @ViewBuilder private func row(_ l: LineDiff.Line) -> some View {
        switch l.kind {
        case .gap:
            Text(l.text.isEmpty ? "···" : "··· " + l.text).font(.system(size: 11)).foregroundStyle(.tertiary)
                .fixedSize().padding(.horizontal, 18).padding(.vertical, 5)
        default:
            HStack(spacing: 0) {
                Text(l.kind == .add ? "+" : l.kind == .del ? "−" : " ").frame(width: 22)
                    .foregroundColor(l.kind == .add ? rgb(0x3fb950) : l.kind == .del ? rgb(0xf85149) : .secondary)
                Text(l.text.isEmpty ? " " : l.text).fixedSize().textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.trailing, 18).padding(.vertical, 1)
            .background(l.kind == .add ? rgb(0x3fb950).opacity(0.13) : l.kind == .del ? rgb(0xf85149).opacity(0.13) : .clear)
        }
    }
}

/// Lo que han hecho tus agentes hoy, para «Hoy» en Ajustes: una línea por aviso en Application Support/Agent Deck/
/// activity/<fecha>.jsonl (carpeta, tipo y la primera frase de lo que dijo). Se queda en el Mac; se borra a los 14 días.
enum Activity {
    struct Day: Equatable { var place: String; var done = 0; var asks = 0; var permissions = 0; var allowed = 0; var autopilot = 0; var last = ""; var lastAt = 0.0 }
    static var folder: URL { Autopilot.folder.appendingPathComponent("activity") }
    static func file(_ date: Date = Date()) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return folder.appendingPathComponent(f.string(from: date) + ".jsonl")
    }
    static func log(_ kind: String, place: String, text: String = "") {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let o: [String: Any] = ["t": Date().timeIntervalSince1970, "kind": kind, "place": String(place.prefix(60)), "text": String(text.prefix(200))]
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return }
        let url = file()
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d + Data([10])); try? h.close() }
        else { try? (d + Data([10])).write(to: url) }
    }
    static func today(_ date: Date = Date()) -> [Day] {
        guard let text = try? String(contentsOf: file(date), encoding: .utf8) else { return [] }
        var days: [String: Day] = [:]
        for line in text.split(separator: "\n") {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let place = (o["place"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Claude Code"
            var d = days[place] ?? Day(place: place)
            switch o["kind"] as? String {
            case "done": d.done += 1
            case "ask": d.asks += 1
            case "permission": d.permissions += 1
            case "allowed": d.allowed += 1
            case "autopilot": d.autopilot += 1
            default: break
            }
            if let t = o["text"] as? String, !t.isEmpty, ["done", "ask"].contains(o["kind"] as? String ?? "") { d.last = t; d.lastAt = o["t"] as? Double ?? 0 }
            days[place] = d
        }
        return days.values.sorted { ($0.done + $0.asks + $0.permissions, $0.place) > ($1.done + $1.asks + $1.permissions, $1.place) }
    }
    /// Los días de más de dos semanas se borran.
    static func prune() {
        let old = Date().addingTimeInterval(-14 * 86_400)
        for f in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < old { try? FileManager.default.removeItem(at: f) }
        }
    }
}

fileprivate func rgb(_ hex: Int) -> Color {
    Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}
