import AppKit
import Darwin
import Foundation
import MacWMCore
import SQLite3

/// Watches the AI coding agents on this Mac, Claude Code, Codex and OpenCode,
/// and summarizes how each is doing: live sessions, whether they are working
/// or waiting, context usage and how much of the plan is used.
final class AgentsMonitor {
    struct Summary {
        let agent: String
        let sessions: Int
        let isWorking: Bool
        let line: String
        let details: String
    }

    private static let agents = ["claude", "codex", "opencode"]
    private var cpuTimes: [pid_t: UInt64] = [:]
    private var codexCache: (path: String, modified: Date, record: AgentStatus?)?

    func summaries() -> [Summary] {
        let processes = runningAgentProcesses()
        let working = workingProcesses(processes)
        var result: [Summary] = []
        for agent in Self.agents {
            let pids = processes.filter { $0.name == agent }.map(\.pid)
            let records = self.records(for: agent)
            guard !pids.isEmpty || !records.isEmpty else { continue }
            let isWorking = pids.contains { working.contains($0) }
            let (line, details) = describe(agent: agent, sessions: pids.count, records: records)
            result.append(Summary(agent: agent, sessions: pids.count, isWorking: isWorking, line: line, details: details))
        }
        return result
    }

    // MARK: - Sources

    private func records(for agent: String) -> [AgentStatus] {
        switch agent {
        case "claude": return claudeRecords()
        case "codex": return codexRecord().map { [$0] } ?? []
        case "opencode": return openCodeRecord().map { [$0] } ?? []
        default: return []
        }
    }

    /// Records written by `macwm agent-status claude` from the status line; fresh within the hour.
    private func claudeRecords() -> [AgentStatus] {
        let directory = URL(fileURLWithPath: AgentStatus.directory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return files
            .filter { $0.lastPathComponent.hasPrefix("claude-") }
            .compactMap { try? decoder.decode(AgentStatus.self, from: Data(contentsOf: $0)) }
            .filter { Date().timeIntervalSince($0.updatedAt) < 3600 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The newest Codex rollout that reports token counts carries the plan's
    /// rate limits and token totals; rollouts without a response have none.
    private func codexRecord() -> AgentStatus? {
        let root = NSString(string: "~/.codex/sessions").expandingTildeInPath
        let candidates = newestFiles(under: root, suffix: ".jsonl", limit: 12)
        guard let latest = candidates.first(where: { fileContains($0, "\"token_count\"") }) else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: latest))?[.modificationDate] as? Date ?? .distantPast
        if let cached = codexCache, cached.path == latest, cached.modified == modified { return cached.record }
        let record = parseCodexRollout(latest, modified: modified)
        codexCache = (latest, modified, record)
        return record
    }

    private func parseCodexRollout(_ latest: String, modified: Date) -> AgentStatus? {
        guard let tail = tail(of: latest, bytes: 1_048_576) else { return nil }
        var limits: [AgentLimit] = []
        var context: Double?
        for line in tail.split(separator: "\n").reversed() {
            guard line.contains("\"token_count\""), let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let payload = json["payload"] as? [String: Any] ?? json
            if let rate = payload["rate_limits"] as? [String: Any] {
                for (key, name) in [("primary", "primary"), ("secondary", "secondary")] {
                    guard let window = rate[key] as? [String: Any], let used = window["used_percent"] as? Double else { continue }
                    let minutes = window["window_minutes"] as? Double ?? 0
                    let label = minutes >= 10080 ? "7d" : (minutes >= 300 ? "\(Int(minutes / 60))h" : name)
                    limits.append(AgentLimit(name: label, usedPercent: used, resetsAt: (window["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }))
                }
            }
            if let info = payload["info"] as? [String: Any], let usage = info["last_token_usage"] as? [String: Any] ?? info["total_token_usage"] as? [String: Any],
               let total = usage["total_tokens"] as? Double, let window = info["model_context_window"] as? Double, window > 0 {
                context = min(100, total / window * 100)
            }
            break
        }
        guard !limits.isEmpty || context != nil else { return nil }
        return AgentStatus(agent: "codex", sessionID: (latest as NSString).lastPathComponent, project: "", model: "", contextUsedPercent: context, limits: limits, updatedAt: modified)
    }

    /// OpenCode keeps token counts per message in its SQLite database.
    private func openCodeRecord() -> AgentStatus? {
        let path = NSString(string: "~/.local/share/opencode/opencode.db").expandingTildeInPath
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { return nil }
        defer { sqlite3_close(database) }
        let query = "select m.data, s.directory, m.time_updated from message m join session s on s.id = m.session_id where m.data like '%\"tokens\"%' order by m.time_updated desc limit 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let dataText = sqlite3_column_text(statement, 0), let directoryText = sqlite3_column_text(statement, 1) else { return nil }
        let updated = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1000)
        guard let json = try? JSONSerialization.jsonObject(with: Data(String(cString: dataText).utf8)) as? [String: Any] else { return nil }
        let tokens = json["tokens"] as? [String: Any] ?? [:]
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let used = (tokens["input"] as? Double ?? 0) + (cache["read"] as? Double ?? 0) + (cache["write"] as? Double ?? 0)
        let model = json["modelID"] as? String ?? ""
        return AgentStatus(agent: "opencode", sessionID: "latest", project: (String(cString: directoryText) as NSString).lastPathComponent, model: "\(model) · \(Int(used / 1000))k tokens", contextUsedPercent: nil, limits: [], updatedAt: updated)
    }

    // MARK: - Processes

    private struct AgentProcess {
        let pid: pid_t
        let name: String
    }

    private func runningAgentProcesses() -> [AgentProcess] {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(count))
        count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var result: [AgentProcess] = []
        for pid in pids.prefix(Int(count) / MemoryLayout<pid_t>.size) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let name = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if Self.agents.contains(name) { result.append(AgentProcess(pid: pid, name: name)) }
        }
        return result
    }

    /// A process is working when it burned CPU since the previous sample.
    private func workingProcesses(_ processes: [AgentProcess]) -> Set<pid_t> {
        var working: Set<pid_t> = []
        var next: [pid_t: UInt64] = [:]
        for process in processes {
            var usage = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(process.pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard status == 0 else { continue }
            let total = usage.ri_user_time + usage.ri_system_time
            next[process.pid] = total
            if let previous = cpuTimes[process.pid], total - previous > 50_000_000 { working.insert(process.pid) }
        }
        cpuTimes = next
        return working
    }

    // MARK: - Formatting

    private func describe(agent: String, sessions: Int, records: [AgentStatus]) -> (String, String) {
        var parts = [agent]
        if sessions > 0 { parts.append("×\(sessions)") }
        if let hottest = records.compactMap(\.hottestLimitPercent).max() { parts.append("plan \(Int(hottest.rounded()))%") }
        if let context = records.compactMap(\.contextUsedPercent).max() { parts.append("ctx \(Int(context.rounded()))%") }
        let details = records.map { record in
            var line = record.project.isEmpty ? record.sessionID : record.project
            if !record.model.isEmpty { line += " · \(record.model)" }
            if let context = record.contextUsedPercent { line += " · context \(Int(context.rounded()))%" }
            if !record.limits.isEmpty { line += " · \(record.limitsSummary)" }
            if let reset = record.limits.compactMap(\.resetsAt).min() {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                line += " · resets \(formatter.string(from: reset))"
            }
            return line
        }.joined(separator: "\n")
        return (parts.joined(separator: " "), details.isEmpty ? "\(agent): \(sessions) running" : details)
    }

    private func newestFiles(under root: String, suffix: String, limit: Int) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var files: [(path: String, date: Date)] = []
        for case let relative as String in enumerator where relative.hasSuffix(suffix) {
            let path = (root as NSString).appendingPathComponent(relative)
            let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
            files.append((path, date))
        }
        return files.sorted { $0.date > $1.date }.prefix(limit).map(\.path)
    }

    private func fileContains(_ path: String, _ needle: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        return data.range(of: Data(needle.utf8)) != nil
    }

    private func tail(of path: String, bytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let size = handle.seekToEndOfFile()
        handle.seek(toFileOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }
}
