import Foundation
import MacWMCore
import MacWMTransport

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    print("Usage: macwm <status|query|reload|layout|focus|move|resize|maximize|toggle-float|toggle-split|close|exec|mode|toggle-terminal|scratchpad|workspace|send-to-workspace> [value]")
    exit(EXIT_FAILURE)
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
