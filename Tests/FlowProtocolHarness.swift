import Foundation

// Synthetic protocol test executable. Storage injection exists only here, never in the production helper.
@main
enum FlowProtocolHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Expected mode and temporary storage path") }
        let mode = CommandLine.arguments[1], folder = URL(fileURLWithPath:CommandLine.arguments[2])
        guard folder.path.hasPrefix("/private/tmp/") || folder.path.hasPrefix("/tmp/") else { fatalError("Synthetic storage must be temporary") }
        let storage = FlowStorage(folder:folder), now = Date().timeIntervalSince1970
        if mode == "seed" {
            try storage.transaction { db in
                db.sessions = [FlowSession(id:"synthetic-chat",cwd:"/synthetic-project",lastSeen:now,state:"running",turnID:"synthetic-turn")]
                var definition = MessageFlow(); definition.mode = "sequence"; definition.steps = ["  primero\ncon detalles  ","segundo","tercero"]
                try db.arm(definition,sessionID:"synthetic-chat",now:now)
            }
            print("{}"); return
        }
        if mode == "read" {
            let data = try JSONEncoder().encode(storage.snapshot())
            FileHandle.standardOutput.write(data); return
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let event = try JSONDecoder().decode(FlowHookEvent.self,from:input)
        let result = try storage.transaction { db in FlowEngine.handle(event,database:&db,now:now) }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result))
    }
}
