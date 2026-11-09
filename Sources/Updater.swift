import AppKit
import Foundation

/// Actualizaciones (0.13): al abrir y una vez al día mira en GitHub si hay una versión más nueva de Agent Bar.
/// Si la hay, lo dice en la barra, el menú y Ajustes, y con «Actualizar» la descarga, comprueba que es Agent Bar firmada
/// con la misma firma que la instalada, la cambia por esta y se reinicia. Teclas, clave y ajustes no se tocan
/// (viven en Application Support). Si algo falla, abre la descarga en la web: nunca deja la app a medias.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "kemet333/agent-deck"

    struct Release: Equatable { let version: String; let notes: String; let page: URL; let dmg: URL }
    @Published private(set) var available: Release?
    @Published private(set) var status = ""
    @Published private(set) var working = false
    private var timer: Timer?

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.check(quiet: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(quiet: true) }
        }
    }

    /// `quiet`: sin mensajes si no hay nada (la comprobación automática).
    func check(quiet: Bool = false) {
        guard !working else { return }
        if !quiet { status = T.s("Checking…", "Comprobando…") }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AgentBar/\(Self.current)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let json, let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                    if !quiet { self.status = T.s("Couldn't check right now.", "Ahora no se ha podido comprobar.") }
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                let dmg = assets.first { ($0["name"] as? String) == "AgentBar.dmg" }?["browser_download_url"] as? String
                if Self.isNewer(version, than: Self.current), let dmg, let url = URL(string: dmg) {
                    let notes = (json["body"] as? String ?? "").split(separator: "\n").map(String.init)
                        .first { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
                    let r = Release(version: version, notes: notes.replacingOccurrences(of: "**", with: ""), page: page, dmg: url)
                    let isNew = self.available != r
                    self.available = r; self.status = ""
                    if isNew { NotificationCenter.default.post(name: Updater.foundNotification, object: nil) }
                } else {
                    self.available = nil
                    if !quiet { self.status = T.s("You have the latest version (\(Self.current)).", "Tienes la última versión (\(Self.current)).") }
                }
            }
        }.resume()
    }
    static let foundNotification = Notification.Name("AgentBarUpdateFound")

    /// 0.12.10 > 0.12.9, número a número.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Descarga, comprueba y cambia la app. Solo si esta copia vive en Aplicaciones; si no, abre la descarga.
    func install() {
        guard let r = available, !working else { return }
        let here = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard here.path.hasPrefix("/Applications/") else { NSWorkspace.shared.open(r.dmg); return }
        working = true; status = T.s("Downloading \(r.version)…", "Descargando la \(r.version)…")
        URLSession.shared.downloadTask(with: r.dmg) { file, _, error in
            // el archivo temporal desaparece al volver: se mueve ya a un sitio propio
            var dmg: URL?
            if let file {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("AgentBar-\(r.version)-\(UUID().uuidString).dmg")
                if (try? FileManager.default.moveItem(at: file, to: dest)) != nil { dmg = dest }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let dmg, error == nil else { self.fallback(r, T.s("The download failed.", "La descarga ha fallado.")); return }
                self.status = T.s("Checking and installing…", "Comprobando e instalando…")
                let app = here
                Task.detached {
                    let result = Updater.swap(dmg: dmg, installed: app)
                    await MainActor.run {
                        switch result {
                        case .success: self.relaunch(app)
                        case .failure(let e): self.fallback(r, e.message)
                        }
                    }
                }
            }
        }.resume()
    }

    private func fallback(_ r: Release, _ why: String) {
        working = false
        status = why + " " + T.s("Opening the download instead.", "Abro la descarga en su lugar.")
        NSWorkspace.shared.open(r.dmg)
    }

    private func relaunch(_ app: URL) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", app.path]
        try? p.run(); NSApp.terminate(nil)
    }

    struct Failure: Error { let message: String }

    /// Monta el instalador, comprueba la app de dentro (misma identidad y misma firma que la instalada) y la cambia.
    nonisolated static func swap(dmg: URL, installed: URL) -> Result<Void, Failure> {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("agentbar-update-\(UUID().uuidString)")
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]); try? fm.removeItem(at: dmg); try? fm.removeItem(at: mount) }
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]).ok else {
            return .failure(Failure(message: T.s("Couldn't open the installer.", "No se ha podido abrir el instalador.")))
        }
        let new = mount.appendingPathComponent("Agent Bar.app")
        guard let b = Bundle(url: new), let ours = Bundle(url: installed)?.bundleIdentifier, b.bundleIdentifier == ours else {
            return .failure(Failure(message: T.s("The download isn't Agent Bar.", "La descarga no es Agent Bar.")))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path]).ok else {
            return .failure(Failure(message: T.s("The new version's signature isn't valid.", "La firma de la versión nueva no es válida.")))
        }
        // misma firma que la instalada: si no, macOS volvería a pedir permisos (o no sería nuestra)
        let mine = run("/usr/bin/codesign", ["-d", "-r-", installed.path]).out, theirs = run("/usr/bin/codesign", ["-d", "-r-", new.path]).out
        guard let a = designated(mine), a == designated(theirs) else {
            return .failure(Failure(message: T.s("The new version is signed differently.", "La versión nueva tiene otra firma.")))
        }
        let staged = installed.deletingLastPathComponent().appendingPathComponent(".Agent Bar update.app")
        try? fm.removeItem(at: staged)
        guard run("/usr/bin/ditto", [new.path, staged.path]).ok else {
            return .failure(Failure(message: T.s("Couldn't copy it into Applications.", "No se ha podido copiar en Aplicaciones.")))
        }
        do {
            _ = try fm.replaceItemAt(installed, withItemAt: staged, backupItemName: nil, options: [])
        } catch {
            try? fm.removeItem(at: staged)
            return .failure(Failure(message: T.s("Couldn't replace the app.", "No se ha podido cambiar la app.")))
        }
        return .success(())
    }
    nonisolated private static func designated(_ s: String) -> String? {
        s.split(separator: "\n").first { $0.hasPrefix("designated =>") }.map(String.init)
    }
    nonisolated private static func run(_ tool: String, _ args: [String]) -> (ok: Bool, out: String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (false, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
