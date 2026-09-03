import Testing
@testable import MacWMCore

@Test func keepsAKeyVisibleThroughASingleMiss() {
    var guardian = FlickerGuard(missesToDrop: 2)
    #expect(guardian.observe(["codex"]) == ["codex"])
    #expect(guardian.observe([]) == ["codex"])
}

@Test func dropsAKeyAfterConsecutiveMisses() {
    var guardian = FlickerGuard(missesToDrop: 2)
    _ = guardian.observe(["codex"])
    _ = guardian.observe([])
    #expect(guardian.observe([]) == [])
}

@Test func showsANewKeyImmediately() {
    var guardian = FlickerGuard(missesToDrop: 2)
    #expect(guardian.observe(["claude"]) == ["claude"])
}
