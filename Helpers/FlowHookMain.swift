import Foundation

@main
enum FlowHookMain {
    static func main() {
        // Production has no environment override or network listener. Tests inject storage directly.
        do {
            let input = try FileHandle.standardInput.read(upToCount: 1_048_577) ?? Data()
            guard input.count <= 1_048_576 else { throw FlowIssue(message: "Hook input too large") }
            let event = try JSONDecoder().decode(FlowHookEvent.self, from: input)
            let result = try FlowStorage.standard.transaction { db in FlowEngine.handle(event, database: &db, now: Date().timeIntervalSince1970) }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        } catch {
            // Fail closed for automation; do not block Codex, change permissions, or echo private input.
            FileHandle.standardOutput.write(Data("{}\n".utf8))
        }
    }
}
