import AppKit
import Foundation

/// Agent Bar Pro: 49 € una sola vez, en 3 Macs, vendido con Lemon Squeezy (decidido por Diego el 08/11/2026).
/// La licencia se activa con la API pública de licencias de Lemon Squeezy (no necesita ninguna clave secreta en la app),
/// se guarda en Application Support/Agent Deck/license.json y se vuelve a comprobar como mucho una vez al día; sin
/// conexión, una licencia activada sigue valiendo.
@MainActor
final class License: ObservableObject {
    static let shared = License()

    /// Se rellenan cuando exista la tienda: solo valen licencias de este producto.
    static let storeID = 0
    static let productID = 0
    static let checkoutURL = URL(string: "https://getagentbar.com/#pricing")!
    /// Mientras sea false, todo sigue gratis (beta): la licencia se puede activar, pero nada se bloquea.
    /// Se enciende cuando exista la tienda de Lemon Squeezy (storeID/productID de arriba).
    static let enforcedSetting = false
    /// Para probar los bloqueos sin encenderlos: AGENT_BAR_ENFORCE_PRO=1 al abrir la app.
    static var enforced: Bool { enforcedSetting || ProcessInfo.processInfo.environment["AGENT_BAR_ENFORCE_PRO"] == "1" }
    /// Pro (decidido por Diego el 14/11/2026: 49 € una vez, 3 Macs). Gratis se queda con Autopilot de 3 vueltas sin objetivo.
    static let freeAutopilotTurns = 3

    struct Saved: Codable { var key: String; var instance: String; var checked: Double; var valid: Bool; var email: String }

    @Published private(set) var saved: Saved?
    @Published var message = ""
    @Published var working = false

    var isPro: Bool { saved?.valid == true }
    /// Lo que la app deja usar: con `enforced` apagado, todo.
    var unlocked: Bool { !Self.enforced || isPro }

    private var file: URL { Autopilot.folder.appendingPathComponent("license.json") }

    init() {
        if let d = try? Data(contentsOf: file) { saved = try? JSONDecoder().decode(Saved.self, from: d) }
        refreshIfNeeded()
    }

    private func store(_ s: Saved?) {
        saved = s
        if let s, let d = try? JSONEncoder().encode(s) {
            try? FileManager.default.createDirectory(at: Autopilot.folder, withIntermediateDirectories: true)
            try? d.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else { try? FileManager.default.removeItem(at: file) }
    }

    private func post(_ path: String, _ fields: [String: String]) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/" + path)!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// ¿Es una licencia de nuestro producto? (si aún no hay tienda configurada, se acepta cualquiera para probar)
    private func ours(_ j: [String: Any]) -> Bool {
        guard Self.storeID != 0 else { return true }
        let meta = j["meta"] as? [String: Any] ?? [:]
        return (meta["store_id"] as? Int) == Self.storeID && (Self.productID == 0 || (meta["product_id"] as? Int) == Self.productID)
    }

    func activate(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8, key.count <= 200 else { message = T.s("Paste the license key from your purchase email.", "Pega la clave de licencia del correo de tu compra."); return }
        working = true; message = T.s("Activating…", "Activando…")
        let name = (Host.current().localizedName ?? "Mac").prefix(60)
        Task {
            let j = await post("activate", ["license_key": key, "instance_name": String(name)])
            working = false
            guard let j else { message = T.s("Couldn't reach Lemon Squeezy. Check your connection.", "No se ha podido conectar con Lemon Squeezy. Revisa la conexión."); return }
            guard j["activated"] as? Bool == true, ours(j), let inst = (j["instance"] as? [String: Any])?["id"] as? String else {
                let err = j["error"] as? String ?? ""
                message = err.contains("limit") ? T.s("This license is already active on 3 Macs. Deactivate one first.", "Esta licencia ya está activa en 3 Macs. Desactívala antes en uno.")
                    : T.s("That license key isn't valid for Agent Bar Pro.", "Esa clave no es válida para Agent Bar Pro.")
                return
            }
            let email = ((j["meta"] as? [String: Any])?["customer_email"] as? String) ?? ""
            store(Saved(key: key, instance: inst, checked: Date().timeIntervalSince1970, valid: true, email: email))
            message = T.s("Pro is on. Thank you!", "Pro activado. ¡Gracias!")
        }
    }

    func deactivate() {
        guard let s = saved else { return }
        working = true
        Task {
            _ = await post("deactivate", ["license_key": s.key, "instance_id": s.instance])
            working = false; store(nil)
            message = T.s("Pro deactivated on this Mac.", "Pro desactivado en este Mac.")
        }
    }

    /// Una vez al día: si Lemon Squeezy dice que ya no vale (reembolso, desactivada), se apaga; sin conexión, sigue.
    func refreshIfNeeded() {
        guard let s = saved, Date().timeIntervalSince1970 - s.checked > 86_400 else { return }
        Task {
            guard let j = await post("validate", ["license_key": s.key, "instance_id": s.instance]) else { return }
            var n = s; n.checked = Date().timeIntervalSince1970; n.valid = (j["valid"] as? Bool == true) && ours(j)
            store(n)
        }
    }
}
