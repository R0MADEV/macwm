import Foundation
import MacWMCore

struct ConfigLoader {
    static let path = NSString(string: "~/.config/macwm/config.toml").expandingTildeInPath

    static func load() -> Config {
        guard let config = loadValidated() else {
            fputs("macwm: invalid configuration at \(path); using defaults.\n", stderr)
            return Config()
        }
        return config
    }

    static func loadValidated() -> Config? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return Config() }
        return Config.parse(text)
    }
}
