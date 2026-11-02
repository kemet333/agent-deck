import Foundation

enum VoiceInsertion: String, Codable, CaseIterable { case paste, direct }
enum VoiceEngine: String, Codable, CaseIterable { case openAI, apple }
enum VoiceTone: String, Codable, CaseIterable {
    case clean, verbatim, formal, casual
    var title: String { switch self { case .clean: return T.s("Clean", "Limpio"); case .verbatim: return T.s("Verbatim", "Literal"); case .formal: return T.s("Formal", "Formal"); case .casual: return T.s("Casual", "Informal") } }
}
enum VoicePurpose: Equatable { case dictation, command, file, summary }
enum VoicePhase: String { case idle, permission, listening, transcribing, cleaning, inserting, draft, failed }
struct VoicePreferences: Codable {
    var engine: VoiceEngine = .openAI
    var fnEnabled = true
    var avoidVowenConflict = true
    var autoPaste = true
    var insertion: VoiceInsertion = .paste
    var autoEnter = false
    var guardTerminal = true
    var transcriptionModel = "gpt-transcribe"
    var textModel = "gpt-5.5"
    var language = ""
    var tone: VoiceTone = .clean
    var dictionary = ""
    var instructions = ""
    var expansions = ""
    var appTones: [String: VoiceTone] = [:]
    var saveHistory = true

    var keywords: [String] { dictionary.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.contains("<") && !$0.contains(">") }.prefix(100).map { String($0.prefix(100)) } }
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
