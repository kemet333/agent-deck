import Foundation

/// La voz incluida de Agent Bar Pro: el servidor de Prompted (server/ en este repositorio) da un permiso temporal de
/// OpenAI por sesión, lleva la cuenta de minutos y limpia o resume texto con su propia clave. Apagado mientras
/// `server` sea nil (aún no está desplegado); con él, la voz de un Pro sin clave propia pasa por aquí.
enum ProVoice {
    static let server: URL? = nil   // p. ej. https://voice.getagentbar.com cuando esté en marcha

    @MainActor static var available: Bool { server != nil && License.shared.isPro && (VoiceKeychain.read() ?? "").isEmpty }

    private static func call(_ path: String, _ extra: [String: Any]) async -> [String: Any]? {
        guard let server, let s = await MainActor.run(body: { License.shared.saved }) else { return nil }
        var req = URLRequest(url: server.appendingPathComponent(path)); req.httpMethod = "POST"; req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["license_key": s.key, "instance_id": s.instance]; extra.forEach { body[$0.key] = $0.value }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    /// Un permiso temporal para una sesión de transcripción en tiempo real (ek_…), y los minutos que quedan.
    static func session() async -> (token: String, model: String, minutesLeft: Int)? {
        guard let j = await call("v1/voice/session", [:]), let t = j["token"] as? String else { return nil }
        return (t, j["model"] as? String ?? "gpt-live-transcribe", j["minutes_left"] as? Int ?? 0)
    }
    static func used(seconds: Double) async { _ = await call("v1/voice/usage", ["seconds": Int(seconds.rounded())]) }
    /// clean | prompt | summary, con las instrucciones del servidor.
    static func text(_ task: String, _ text: String) async -> String? { await call("v1/text", ["task": task, "text": text])?["text"] as? String }
}
