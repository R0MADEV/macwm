import Foundation
import MacWMCore

struct WorkspacePersistence: Sendable {
    static let path = NSString(string: "~/.config/macwm/state.json").expandingTildeInPath

    private struct Entry: Codable {
        let bundleIdentifier: String
        let title: String
        let processID: UInt32?
        let workspace: Int
    }

    struct State: Codable, Sendable {
        let activeWorkspace: Int
        let assignments: [WindowKey: Int]
        let trees: [Int: WindowTree]?
        let layouts: [Int: LayoutKind]?
        let barPosition: BarPosition?
        let floating: [WindowKey: Bool]?
        let maximized: [WindowKey: Frame]?
    }

    func load() -> [WindowKey: Int] {
        loadState().assignments
    }

    func loadState() -> State {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)) else {
            return State(activeWorkspace: 1, assignments: [:], trees: nil, layouts: nil, barPosition: nil, floating: nil, maximized: nil)
        }
        if let state = try? JSONDecoder().decode(State.self, from: data) { return state }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return State(activeWorkspace: 1, assignments: [:], trees: nil, layouts: nil, barPosition: nil, floating: nil, maximized: nil)
        }
        let assignments = entries.reduce(into: [WindowKey: Int]()) { result, entry in
            result[WindowKey(bundleIdentifier: entry.bundleIdentifier, title: entry.title, processID: entry.processID)] = entry.workspace
        }
        return State(activeWorkspace: 1, assignments: assignments, trees: nil, layouts: nil, barPosition: nil, floating: nil, maximized: nil)
    }

    func save(_ assignments: [WindowKey: Int], activeWorkspace: Int = 1, trees: [Int: WindowTree] = [:], layouts: [Int: LayoutKind] = [:], barPosition: BarPosition? = nil, floating: [WindowKey: Bool]? = nil, maximized: [WindowKey: Frame]? = nil) {
        let previous = loadState()
        let state = State(activeWorkspace: activeWorkspace, assignments: assignments, trees: trees, layouts: layouts, barPosition: barPosition ?? previous.barPosition, floating: floating ?? previous.floating, maximized: maximized ?? previous.maximized)
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = URL(fileURLWithPath: Self.path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
