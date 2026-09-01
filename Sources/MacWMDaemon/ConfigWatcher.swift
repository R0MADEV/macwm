import Foundation
import MacWMCore

/// Applies configuration changes as soon as the file is saved, like Hyprland.
/// Watches the directory for atomic saves (editors rename a temporary file
/// into place) and the file itself for in-place writes; events are debounced
/// so a save produces one reload.
final class ConfigWatcher {
    private let directory: String
    private let onChange: () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(directory: String, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    func start() {
        directorySource = watch(path: directory) { [weak self] in
            self?.watchConfigFile()
            self?.scheduleReload()
        }
        watchConfigFile()
    }

    private func watchConfigFile() {
        fileSource?.cancel()
        fileSource = nil
        guard let path = ConfigFile.read()?.path else { return }
        fileSource = watch(path: path) { [weak self] in self?.scheduleReload() }
    }

    private func watch(path: String, handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
