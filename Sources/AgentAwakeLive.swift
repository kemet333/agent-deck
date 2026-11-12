import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// El vigilante de AgentAwake: cada 10 s mira los procesos (`ps`, fuera del hilo principal), decide y pone o quita la
/// petición a macOS de no dormir por inactividad (la pantalla sí puede apagarse). `pmset -g assertions` la enseña
/// con su motivo, «Agent Bar: Claude Code trabajando».
@MainActor
final class AgentAwakeMonitor: ObservableObject {
    static let shared = AgentAwakeMonitor()
    @Published private(set) var decision: AgentAwake.Decision = .idle
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "keepAwakeForAgents"); tick() }
    }
    private var timer: Timer?
    private var before: [Int32: AgentAwake.Tree] = [:]
    private var lastWork: [String: Date] = [:]
    private var assertion: IOPMAssertionID = 0
    private var held = false
    private var sampling = false

    init() { enabled = UserDefaults.standard.object(forKey: "keepAwakeForAgents") as? Bool ?? true }

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func stop() { timer?.invalidate(); timer = nil; release() }

    private func tick() {
        guard !sampling else { return }
        guard enabled else { lastWork = [:]; before = [:]; apply(.idle); return }
        sampling = true
        DispatchQueue.global(qos: .utility).async {
            let procs = AgentAwake.parse(Self.run(["-axS", "-o", "pid=,ppid=,time=,comm="]))
            // Gemini y otros corren en node: se mira su orden solo en los node
            let nodes = procs.filter { $0.name == "node" }.map(\.pid)
            var nodeAgents: [Int32: String] = [:]
            if !nodes.isEmpty {
                for line in Self.run(["-o", "pid=,args=", "-p", nodes.map(String.init).joined(separator: ",")]).split(separator: "\n") {
                    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
                    let args = parts[1].lowercased()
                    if args.contains("/gemini") || args.contains("gemini-cli") { nodeAgents[pid] = "Gemini" }
                    else if args.contains("/qwen") { nodeAgents[pid] = "Qwen" }
                }
            }
            let trees = AgentAwake.agentTrees(procs, nodeAgents: nodeAgents)
            Task { @MainActor in self.sampled(trees) }
        }
    }
    private func sampled(_ trees: [Int32: AgentAwake.Tree]) {
        sampling = false
        let now = Date()
        for name in AgentAwake.working(before: before, now: trees) { lastWork[name] = now }
        before = trees
        lastWork = lastWork.filter { now.timeIntervalSince($0.value) <= 300 }
        let names = lastWork.sorted { $0.value > $1.value }.map(\.key)
        apply(AgentAwake.decide(enabled: enabled, lastWork: lastWork.values.max(), names: names, now: now, power: Self.power()))
    }

    private func apply(_ d: AgentAwake.Decision) {
        if decision != d { decision = d }
        if case .awake(let names) = d { hold(T.s("Agent Bar: \(AgentAwake.list(names)) working", "Agent Bar: \(AgentAwake.list(names)) trabajando")) } else { release() }
    }
    private func hold(_ reason: String) {
        guard !held else { return }
        held = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &assertion) == kIOReturnSuccess
    }
    private func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion); held = false; assertion = 0
    }

    /// Lo que se ve en Ajustes: «Despierto: Claude Code trabajando» / «En reposo» / «No: batería por debajo del 30 %».
    var status: String {
        switch decision {
        case .awake(let n): return T.s("Awake now: \(AgentAwake.list(n)) working", "Despierto ahora: \(AgentAwake.list(n)) trabajando")
        case .idle: return enabled ? T.s("No agent working: the Mac can sleep as usual", "Ningún agente trabajando: el Mac duerme como siempre") : T.s("Off", "Apagado")
        case .blocked(let why): return T.s("Agents working, but letting it sleep: \(why)", "Hay agentes trabajando, pero lo dejo dormir: \(why)")
        }
    }

    nonisolated static func power() -> AgentAwake.Power {
        var p = AgentAwake.Power(onBattery: false, level: 100, hot: ProcessInfo.processInfo.thermalState == .critical)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return p }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            p.onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 { p.level = cur * 100 / max }
        }
        return p
    }
    nonisolated static func run(_ args: [String]) -> String {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/bin/ps"); t.arguments = args
        let out = Pipe(); t.standardOutput = out; t.standardError = FileHandle.nullDevice
        guard (try? t.run()) != nil else { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile(); t.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}
