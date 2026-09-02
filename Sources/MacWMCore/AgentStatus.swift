import Foundation

/// A usage window of an AI coding agent's plan, such as Claude's five-hour limit.
public struct AgentLimit: Codable, Equatable, Sendable {
    public let name: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(name: String, usedPercent: Double, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// What the bar shows for one agent session: which agent, which project,
/// how full its context is and how much of the plan it has used.
public struct AgentStatus: Codable, Equatable, Sendable {
    public static let directory = NSString(string: "~/.config/macwm/agents").expandingTildeInPath

    public let agent: String
    public let sessionID: String
    public let project: String
    public let model: String
    public let contextUsedPercent: Double?
    public let limits: [AgentLimit]
    public let updatedAt: Date

    public init(agent: String, sessionID: String, project: String, model: String, contextUsedPercent: Double?, limits: [AgentLimit], updatedAt: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.project = project
        self.model = model
        self.contextUsedPercent = contextUsedPercent
        self.limits = limits
        self.updatedAt = updatedAt
    }

    /// Reads the JSON Claude Code pipes to a status line command.
    public static func fromClaudeStatusLine(_ data: Data, now: Date = Date()) -> AgentStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sessionID = json["session_id"] as? String else { return nil }
        let cwd = json["cwd"] as? String ?? ""
        let model = (json["model"] as? [String: Any])?["display_name"] as? String ?? ""
        let context = (json["context_window"] as? [String: Any])?["used_percentage"] as? Double
        let rateLimits = json["rate_limits"] as? [String: Any] ?? [:]
        let limits = [("five_hour", "5h"), ("seven_day", "7d"), ("spend_limit", "spend")].compactMap { key, name -> AgentLimit? in
            guard let window = rateLimits[key] as? [String: Any], let used = window["used_percentage"] as? Double else { return nil }
            let resets = (window["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return AgentLimit(name: name, usedPercent: used, resetsAt: resets)
        }
        return AgentStatus(
            agent: "claude",
            sessionID: sessionID,
            project: (cwd as NSString).lastPathComponent,
            model: model,
            contextUsedPercent: context,
            limits: limits,
            updatedAt: now
        )
    }

    public static func fileName(agent: String, sessionID: String) -> String {
        let safe = sessionID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return "\(agent)-\(String(safe)).json"
    }

    public var limitsSummary: String {
        limits.map { "\($0.name) \(Int($0.usedPercent.rounded()))%" }.joined(separator: " · ")
    }

    public var hottestLimitPercent: Double? {
        limits.map(\.usedPercent).max()
    }
}
