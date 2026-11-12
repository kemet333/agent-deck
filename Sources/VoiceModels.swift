import Foundation

enum VoiceInsertion: String, Codable, CaseIterable { case paste, direct }
enum VoiceEngine: String, Codable, CaseIterable { case openAI, apple }
enum VoiceTone: String, Codable, CaseIterable {
    case clean, verbatim, formal, casual, prompt
    var title: String { switch self { case .clean: return T.s("Clean", "Limpio"); case .verbatim: return T.s("Verbatim", "Literal"); case .formal: return T.s("Formal", "Formal"); case .casual: return T.s("Casual", "Informal"); case .prompt: return T.s("Prompt for an AI", "Prompt para una IA") } }
}
enum VoicePurpose: Equatable { case dictation, command, file, summary }
enum VoicePhase: String { case idle, permission, listening, transcribing, cleaning, inserting, draft, failed }
struct VoicePreferences: Codable {
    var engine: VoiceEngine = .openAI
    var fnEnabled = true
    /// La tecla para hablar (0.20): Fn o la que elijas (el Fn de teclados como el Aula F75 no llega al Mac).
    var talkKey: TalkKey = .fn
    var avoidVowenConflict = false // Agent Bar se queda Fn antes que Vowen (tap en cabeza que consume la tecla); Diego usa las dos (06/11)
    var autoPaste = true
    var insertion: VoiceInsertion = .paste
    var autoEnter = true // al soltar Fn se envía (petición de Diego, 06/11); los terminales siguen protegidos
    var guardTerminal = true
    var transcriptionModel = "gpt-transcribe"
    var textModel = "gpt-5.5"
    var language = ""
    /// Idiomas que se le dicen a OpenAI. Sin uno elegido: el del Mac y el inglés (así una frase corta no sale en hindi o en ruso).
    var spokenLanguages: [String] {
        let chosen = language.trimmingCharacters(in: .whitespaces).lowercased()
        if !chosen.isEmpty { return [String(chosen.prefix(2))] }
        let mac = String((Locale.preferredLanguages.first ?? "en").prefix(2)).lowercased()
        return mac == "en" ? ["en"] : [mac, "en"]
    }
    var tone: VoiceTone = .clean
    var dictionary = ""
    var instructions = ""
    var expansions = ""
    var appTones: [String: VoiceTone] = [:]
    var saveHistory = true
    /// En los chats de IA (Claude, ChatGPT, Cursor, Codex), lo dictado de más de 12 palabras se convierte en un prompt.
    var promptInAIApps = true
    /// Transcribir mientras hablas (Realtime de OpenAI); al soltar Fn el texto ya está casi listo.
    var streaming = true
    var liveModel = "gpt-live-transcribe"
    /// Ver lo que se va oyendo mientras hablas (apagado: solo la luz; la ventaja es la rapidez al soltar).
    var showLiveText = false
    /// Aprender los nombres de tus proyectos (carpetas con git) para escribirlos bien.
    var learnVocabulary = true

    var keywords: [String] {
        let mine = dictionary.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.contains("<") && !$0.contains(">") }
        // y los nombres de tus proyectos que Agent Bar aprende solo (sin repetir los tuyos)
        // y el vocabulario de tu equipo (0.19), si sigues uno
        var lower = Set(mine.map { $0.lowercased() })
        let team = TeamVocabulary.cached.filter { lower.insert($0.lowercased()).inserted }
        return (mine + team + (learnVocabulary ? LearnedVocabulary.cached.filter { !lower.contains($0.lowercased()) } : [])).prefix(100).map { String($0.prefix(100)) }
    }
    func tone(for bundle: String?) -> VoiceTone { bundle.flatMap { appTones[$0] } ?? tone }
    func expand(_ text: String) -> String {
        var result = text
        let pairs = expansions.components(separatedBy: .newlines).compactMap { line -> (String, String)? in
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let k = parts[0].trimmingCharacters(in: .whitespaces), v = parts[1].trimmingCharacters(in: .whitespaces)
            return !k.isEmpty && !v.isEmpty && k.count <= 100 && v.count <= 4000 ? (k, v) : nil
        }.sorted { $0.0.count > $1.0.count }.prefix(100)
        // A single pass prevents one expansion from triggering another expansion.
        guard !pairs.isEmpty else { return result }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + pairs.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return result }
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(m.range, in: result), let original = Range(m.range, in: text) else { continue }
            if let pair = pairs.first(where: { $0.0.caseInsensitiveCompare(String(text[original])) == .orderedSame }) { result.replaceSubrange(range, with: pair.1) }
        }
        return result
    }
}
struct VoiceDraft: Codable { var text:String;var source:String;var date=Date() }
struct VoiceRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
    var source: String
    var kind: String
}
struct VoiceStorage {
    let folder: URL
    init(folder: URL) { self.folder = folder }
    func loadPreferences() -> VoicePreferences { (try? JSONDecoder().decode(VoicePreferences.self, from: Data(contentsOf: folder.appendingPathComponent("voice-settings.json")))) ?? VoicePreferences() }
    func loadDraft()->VoiceDraft?{try? JSONDecoder().decode(VoiceDraft.self,from:Data(contentsOf:folder.appendingPathComponent("voice-draft.json")))}
    func loadHistory() -> [VoiceRecord] { Array(((try? JSONDecoder().decode([VoiceRecord].self, from: Data(contentsOf: folder.appendingPathComponent("voice-history.json")))) ?? []).prefix(100)) }
    func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(name), data = try JSONEncoder().encode(value)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

// No AppKit dependency: exact Fn gesture semantics can be tested without a real keyboard or microphone.
struct FnGesture {
    enum State: Equatable { case idle, pending(TimeInterval), holding, locked, armed(TimeInterval) }
    enum Action: Equatable { case start, stop, cancel }
    private(set) var state: State = .idle
    mutating func down(at time: TimeInterval) -> [Action] {
        switch state {
        case .locked: state = .idle; return [.stop]
        case .holding, .pending: return []
        case .armed(let until) where time <= until: state = .locked; return [.start]
        default: state = .pending(time); return []
        }
    }
    mutating func held(at time: TimeInterval) -> [Action] {
        if case .pending(let since) = state, time - since >= 0.18 { state = .holding; return [.start] }
        return []
    }
    mutating func up(at time: TimeInterval) -> [Action] {
        switch state {
        case .pending: state = .armed(time + 0.5); return []
        case .holding: state = .idle; return [.stop]
        default: return []
        }
    }
    mutating func handsFree() -> [Action] {
        switch state {
        case .pending, .idle, .armed: state = .locked; return [.start]
        case .holding: state = .locked; return []
        case .locked: return []
        }
    }
    mutating func cancel() -> [Action] {
        let active = state == .holding || state == .locked
        state = .idle
        return active ? [.cancel] : []
    }
}

/// Los ajustes guardados por versiones anteriores no traen los campos nuevos: se leen uno a uno y lo que falta
/// toma su valor por defecto, en vez de perder todos los ajustes.
extension VoicePreferences {
    private enum K: String, CodingKey { case engine, fnEnabled, talkKey, avoidVowenConflict, autoPaste, insertion, autoEnter, guardTerminal, transcriptionModel, textModel, language, tone, dictionary, instructions, expansions, appTones, saveHistory, promptInAIApps, streaming, liveModel, showLiveText, learnVocabulary }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: K.self)
        engine = (try? c.decodeIfPresent(VoiceEngine.self, forKey: .engine)) ?? engine
        fnEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .fnEnabled)) ?? fnEnabled
        talkKey = (try? c.decodeIfPresent(TalkKey.self, forKey: .talkKey)) ?? talkKey
        avoidVowenConflict = (try? c.decodeIfPresent(Bool.self, forKey: .avoidVowenConflict)) ?? avoidVowenConflict
        autoPaste = (try? c.decodeIfPresent(Bool.self, forKey: .autoPaste)) ?? autoPaste
        insertion = (try? c.decodeIfPresent(VoiceInsertion.self, forKey: .insertion)) ?? insertion
        autoEnter = (try? c.decodeIfPresent(Bool.self, forKey: .autoEnter)) ?? autoEnter
        guardTerminal = (try? c.decodeIfPresent(Bool.self, forKey: .guardTerminal)) ?? guardTerminal
        transcriptionModel = (try? c.decodeIfPresent(String.self, forKey: .transcriptionModel)) ?? transcriptionModel
        textModel = (try? c.decodeIfPresent(String.self, forKey: .textModel)) ?? textModel
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? language
        tone = (try? c.decodeIfPresent(VoiceTone.self, forKey: .tone)) ?? tone
        dictionary = (try? c.decodeIfPresent(String.self, forKey: .dictionary)) ?? dictionary
        instructions = (try? c.decodeIfPresent(String.self, forKey: .instructions)) ?? instructions
        expansions = (try? c.decodeIfPresent(String.self, forKey: .expansions)) ?? expansions
        appTones = (try? c.decodeIfPresent([String: VoiceTone].self, forKey: .appTones)) ?? appTones
        saveHistory = (try? c.decodeIfPresent(Bool.self, forKey: .saveHistory)) ?? saveHistory
        promptInAIApps = (try? c.decodeIfPresent(Bool.self, forKey: .promptInAIApps)) ?? promptInAIApps
        streaming = (try? c.decodeIfPresent(Bool.self, forKey: .streaming)) ?? streaming
        liveModel = (try? c.decodeIfPresent(String.self, forKey: .liveModel)) ?? liveModel
        showLiveText = (try? c.decodeIfPresent(Bool.self, forKey: .showLiveText)) ?? showLiveText
        learnVocabulary = (try? c.decodeIfPresent(Bool.self, forKey: .learnVocabulary)) ?? learnVocabulary
    }
    /// Chats y editores de IA donde «Voz → prompt» tiene sentido.
    static let aiApps: Set<String> = ["com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "ai.perplexity.mac"]
}
