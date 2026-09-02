import Foundation
import MacWMCore
import MacWMTransport

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    print("Usage: macwm <status|query|reload|layout|focus|move|resize|maximize|toggle-float|toggle-split|close|exec|mode|toggle-terminal|scratchpad|workspace|send-to-workspace> [value]")
    exit(EXIT_FAILURE)
}

// `macwm agent-status claude` sits in Claude Code's status line pipeline: it
// records the session's usage for macwm-bar and passes the JSON through.
if command == "agent-status" {
    let agent = arguments.dropFirst().first ?? ""
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if agent == "claude", let status = AgentStatus.fromClaudeStatusLine(input) {
        let directory = URL(fileURLWithPath: AgentStatus.directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(status).write(to: directory.appendingPathComponent(AgentStatus.fileName(agent: "claude", sessionID: status.sessionID)), options: .atomic)
    }
    FileHandle.standardOutput.write(input)
    exit(EXIT_SUCCESS)
}

guard let parsedCommand = Command.parse(arguments) else {
    print("macwm: invalid command")
    exit(EXIT_FAILURE)
}

let client = UnixSocketClient(path: "/tmp/macwm.sock")
guard let response = client.send(parsedCommand) else {
    print("macwm: daemon is not running or IPC socket is unavailable")
    exit(EXIT_FAILURE)
}

print(response)
