import AppKit
import SwiftUI

/// Una sesión de Claude Code, tal como la deja el gancho en Application Support/Agent Deck/sessions/<id>.json:
/// carpeta, estado (trabajando, te espera, terminado), la herramienta que usa y desde cuándo. Nunca el contenido.
struct AgentSession: Equatable, Identifiable {
    enum State: String { case working, needs, done, idle }
    let id: String
    let place: String
    let state: State
    let tool: String
    let detail: String
    let host: String
    let started: Date
    let updated: Date

    /// Las sesiones vivas, de la más urgente a la menos: te esperan, trabajando, terminadas.
    static func load(from folder: URL, now: Date = Date()) -> [AgentSession] {
        let dir = folder.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [AgentSession] = []
        for f in files where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let id = o["id"] as? String, let st = State(rawValue: o["state"] as? String ?? "") else { continue }
            let updated = Date(timeIntervalSince1970: o["updated"] as? Double ?? 0)
            let age = now.timeIntervalSince(updated)
            // terminadas: se ven 20 min; trabajando sin señal 45 min: se da por cerrada; nada de hace más de 6 h
            if age > 6 * 3600 { try? FileManager.default.removeItem(at: f); continue }
            if st == .done && age > 20 * 60 { continue }
            if st == .idle { continue }
            if st == .working && age > 45 * 60 { continue }
            out.append(AgentSession(id: id, place: o["place"] as? String ?? "?", state: st, tool: o["tool"] as? String ?? "",
                                    detail: o["detail"] as? String ?? "", host: o["host"] as? String ?? "",
                                    started: Date(timeIntervalSince1970: o["started"] as? Double ?? updated.timeIntervalSince1970), updated: updated))
        }
        let rank: [State: Int] = [.needs: 0, .working: 1, .done: 2, .idle: 3]
        return out.sorted { (rank[$0.state] ?? 9, $1.updated) < (rank[$1.state] ?? 9, $0.updated) }
    }
}

extension DeskStore {
    /// Encima de la barra: tus sesiones de Claude Code (Ajustes → Avisos). Encendido por defecto.
    var showAgents: Bool {
        get { UserDefaults.standard.object(forKey: "showAgents") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showAgents"); objectWillChange.send() }
    }
}

/// La franja de agentes: una pastilla por sesión. Clic: trae delante la app donde corre.
struct AgentStrip: View {
    let agents: [AgentSession]
    @Environment(\.barTheme) private var th
    var body: some View {
        HStack(spacing: 6) {
            ForEach(agents.prefix(4)) { a in AgentChip(agent: a) }
            if agents.count > 4 {
                Text("+\(agents.count - 4)").font(.system(size: 10.5, weight: .semibold)).foregroundColor(th.mute)
                    .padding(.horizontal, 8).frame(height: 26).modifier(Surface(radius: 13))
            }
        }
    }
}

struct AgentChip: View {
    let agent: AgentSession
    @Environment(\.barTheme) private var th
    @State private var hover = false
    private var color: Color {
        switch agent.state {
        case .needs: return Color(hex: 0xff9f0a)
        case .working: return th.accent
        case .done, .idle: return Color(hex: 0x30d158)
        }
    }
    private var status: String {
        switch agent.state {
        case .needs: return T.s("needs you", "te espera")
        case .done, .idle: return T.s("done", "terminado")
        case .working: return agent.tool.isEmpty ? T.s("thinking", "pensando") : agent.tool
        }
    }
    var body: some View {
        Button { DeskStore.openHost(agent.host) } label: {
            HStack(spacing: 7) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: agent.state == .done)) { ctx in
                    let p = agent.state == .done ? 0.5 : 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * (agent.state == .needs ? 5 : 2.6))
                    Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.3 + 0.5 * p), radius: 1.5 + 4 * p)
                }.frame(width: 8, height: 8)
                Text(agent.place).font(.system(size: 11, weight: .semibold)).foregroundColor(th.ink).lineLimit(1).frame(maxWidth: 110, alignment: .leading).fixedSize()
                Text(status).font(.system(size: 11)).foregroundColor(agent.state == .needs ? color : th.mute).lineLimit(1).fixedSize()
                if agent.state == .working {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Self.elapsed(ctx.date.timeIntervalSince(agent.started))).font(.system(size: 10.5).monospacedDigit()).foregroundColor(th.faint)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 10).frame(height: 26)
            .modifier(Surface(radius: 13))
            .scaleEffect(hover ? 1.04 : 1)
            .animation(Motion.tap, value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(agent.detail.isEmpty ? agent.place : "\(agent.place) · \(agent.tool) · \(agent.detail)")
    }
    static func elapsed(_ s: Double) -> String {
        let m = Int(s) / 60
        return m < 1 ? "\(Int(s))s" : m < 60 ? "\(m) min" : "\(m / 60) h"
    }
}
