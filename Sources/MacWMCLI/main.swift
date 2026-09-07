import Foundation
import MacWMCore
import MacWMTransport

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    print("Usage: macwm <status|query|reload|layout|focus|move|resize|maximize|toggle-float|toggle-split|close|exec|mode|toggle-terminal|scratchpad|workspace|send-to-workspace|restart> [value]")
    exit(EXIT_FAILURE)
}

// Kills and relaunches the daemon and the bar through launchd, for when
// either gets stuck: a frozen bar showing a stale workspace, a daemon that
// stopped responding. Goes straight to launchctl instead of the daemon's own
// socket, since the daemon being unresponsive is exactly the case this must
// still work in.
if command == "restart" {
    for label in ["com.macwm.daemon", "com.macwm.bar"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        try? process.run()
        process.waitUntilExit()
    }
    print("macwm: restarted daemon and bar")
    exit(EXIT_SUCCESS)
}

// `macwm agent-status claude` sits in Claude Code's status line pipeline: it
// records the session's usage for macwm-bar and passes the JSON through.
if command == "agent-status" {
    let agent = arguments.dropFirst().first ?? ""
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if agent == "claude", let status = AgentStatus.fromClaudeStatusLine(input, configDirectory: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]) {
        let directory = URL(fileURLWithPath: AgentStatus.directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(status).write(to: directory.appendingPathComponent(AgentStatus.fileName(agent: "claude", sessionID: status.sessionID, account: status.account)), options: .atomic)
    }
    // --render prints a status line instead of passing the JSON through, for
    // accounts that had no status line configured.
    if arguments.contains("--render") {
        if let status = AgentStatus.fromClaudeStatusLine(input, configDirectory: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]) {
            print(status.statusLineText)
        }
        exit(EXIT_SUCCESS)
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
