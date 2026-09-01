import Darwin
import Foundation
import MacWMCore

public final class UnixSocketServer: @unchecked Sendable {
    private let path: String
    private let fileDescriptor: Int32
    private let source: DispatchSourceRead
    private let handler: (Command) -> String

    public init?(path: String, handler: @escaping (Command) -> String) {
        self.path = path
        self.handler = handler

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        fileDescriptor = descriptor

        _ = path.withCString { unlink($0) }
        var address = sockaddr_un()
        guard UnixSocketAddress.write(path, to: &address) else {
            close(descriptor)
            return nil
        }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            _ = path.withCString { unlink($0) }
            return nil
        }

        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.setCancelHandler { [path] in
            close(descriptor)
            _ = path.withCString { unlink($0) }
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    private func acceptConnection() {
        let client = accept(fileDescriptor, nil, nil)
        guard client >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else {
            close(client)
            return
        }

        let input = String(decoding: buffer[..<count], as: UTF8.self)
        let arguments = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        let response = Command.parse(arguments).map(handler) ?? "error: invalid command"
        let output = Array((response + "\n").utf8)
        var offset = 0
        while offset < output.count {
            let written = output[offset...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            guard written > 0 else { break }
            offset += written
        }
        close(client)
    }
}

public struct UnixSocketClient: Sendable {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public func send(_ command: Command) -> String? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_un()
        guard UnixSocketAddress.write(path, to: &address) else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let input = Array((command.wireValue + "\n").utf8)
        guard input.withUnsafeBytes({ write(descriptor, $0.baseAddress, input.count) }) == input.count else { return nil }

        // Responses such as query state exceed one buffer; read until the daemon closes.
        var response: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            response.append(contentsOf: buffer[..<count])
        }
        guard !response.isEmpty else { return nil }
        return String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum UnixSocketAddress {
    static func write(_ path: String, to address: inout sockaddr_un) -> Bool {
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count + 1 <= capacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            for index in 0..<destination.count {
                destination[index] = 0
            }
            destination.copyBytes(from: bytes)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        return true
    }
}

/// Pushes newline-delimited messages to every connected client, for bars and
/// scripts that want events instead of polling. Clients that stop reading are
/// dropped on the next write.
public final class UnixSocketBroadcaster: @unchecked Sendable {
    private let path: String
    private let fileDescriptor: Int32
    private let source: DispatchSourceRead
    private var clients: [Int32] = []

    public init?(path: String) {
        self.path = path
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        fileDescriptor = descriptor

        _ = path.withCString { unlink($0) }
        var address = sockaddr_un()
        guard UnixSocketAddress.write(path, to: &address) else {
            close(descriptor)
            return nil
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            _ = path.withCString { unlink($0) }
            return nil
        }

        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.setCancelHandler { [path] in
            close(descriptor)
            _ = path.withCString { unlink($0) }
        }
        source.resume()
    }

    deinit {
        for client in clients { close(client) }
        source.cancel()
    }

    public func broadcast(_ message: String) {
        let output = Array((message + "\n").utf8)
        // Never wait on a client: one that stopped reading is dropped.
        clients.removeAll { client in
            let written = output.withUnsafeBytes { send(client, $0.baseAddress, output.count, MSG_DONTWAIT) }
            let isDead = written != output.count
            if isDead { close(client) }
            return isDead
        }
    }

    private func acceptConnection() {
        let client = accept(fileDescriptor, nil, nil)
        guard client >= 0 else { return }
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        clients.append(client)
    }
}
