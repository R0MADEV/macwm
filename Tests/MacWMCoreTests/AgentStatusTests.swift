import Foundation
import Testing
@testable import MacWMCore

private let sample = """
{"session_id":"abc-123","cwd":"/Users/roma/Desktop/roma/macwm","model":{"id":"claude-fable-5-1","display_name":"Fable 5.1"},
 "context_window":{"context_window_size":200000,"used_percentage":42.5,"remaining_percentage":57.5},
 "rate_limits":{"five_hour":{"used_percentage":37,"resets_at":1790000000},"seven_day":{"used_percentage":12.25,"resets_at":1790500000}},
 "cost":{"total_cost_usd":1.5}}
"""

@Test func parsesClaudeStatusLineJSON() throws {
    let status = try #require(AgentStatus.fromClaudeStatusLine(Data(sample.utf8), now: Date(timeIntervalSince1970: 1_789_000_000)))

    #expect(status.agent == "claude")
    #expect(status.sessionID == "abc-123")
    #expect(status.project == "macwm")
    #expect(status.model == "Fable 5.1")
    #expect(status.contextUsedPercent == 42.5)
    #expect(status.limits == [
        AgentLimit(name: "5h", usedPercent: 37, resetsAt: Date(timeIntervalSince1970: 1_790_000_000)),
        AgentLimit(name: "7d", usedPercent: 12.25, resetsAt: Date(timeIntervalSince1970: 1_790_500_000))
    ])
    #expect(status.updatedAt == Date(timeIntervalSince1970: 1_789_000_000))
    #expect(AgentStatus.fromClaudeStatusLine(Data("{}".utf8)) == nil)
    #expect(AgentStatus.fromClaudeStatusLine(Data("not json".utf8)) == nil)
}

@Test func statusRoundTripsThroughJSON() throws {
    let status = try #require(AgentStatus.fromClaudeStatusLine(Data(sample.utf8)))

    let decoded = try JSONDecoder().decode(AgentStatus.self, from: JSONEncoder().encode(status))

    #expect(decoded == status)
    #expect(AgentStatus.fileName(agent: "claude", sessionID: "abc/123 x") == "claude-abc_123_x.json")
}

@Test func summarizesLimitsForTheBar() throws {
    let status = try #require(AgentStatus.fromClaudeStatusLine(Data(sample.utf8)))

    #expect(status.limitsSummary == "5h 37% · 7d 12%")
    #expect(status.hottestLimitPercent == 37)
}

@Test func accountComesFromTheConfigDirectory() throws {
    let status = try #require(AgentStatus.fromClaudeStatusLine(Data(sample.utf8), configDirectory: "/Users/roma/.claude-max"))

    #expect(status.account == "max")
    #expect(AgentStatus.accountName(fromConfigDirectory: "/Users/roma/.claude-pro") == "pro")
    #expect(AgentStatus.accountName(fromConfigDirectory: nil) == "")
    #expect(AgentStatus.accountName(fromConfigDirectory: "/Users/roma/.claude") == "")
    #expect(AgentStatus.fileName(agent: "claude", sessionID: "abc", account: "max") == "claude-max-abc.json")
}
