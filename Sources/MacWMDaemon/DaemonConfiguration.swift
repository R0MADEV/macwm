import MacWMCore

final class DaemonConfiguration: @unchecked Sendable {
    var value: Config

    init(_ value: Config) {
        self.value = value
    }
}
