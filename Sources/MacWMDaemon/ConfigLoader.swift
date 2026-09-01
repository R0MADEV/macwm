import Foundation
import MacWMCore

struct ConfigLoader {
    static func load() -> Config {
        guard let config = loadValidated() else {
            fputs("macwm: invalid configuration at \(ConfigFile.read()?.path ?? ConfigFile.tomlPath); using defaults.\n", stderr)
            return Config()
        }
        return config
    }

    static func loadValidated() -> Config? {
        guard let file = ConfigFile.read() else { return Config() }
        return ConfigFile.parse(file.text, isHyprland: file.isHyprland)
    }
}
