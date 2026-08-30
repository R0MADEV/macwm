import Testing
@testable import MacWMCore

@Test func parsesFloatingBundleRule() {
    let config = Config.parse("""
    [[rules]]
    bundle_id = "com.apple.Finder"
    float = true
    """)

    #expect(config?.rules == [WindowRule(bundleIdentifier: "com.apple.Finder", float: true)])
}

@Test func ruleMatchesOnlyItsBundleIdentifier() {
    let rule = WindowRule(bundleIdentifier: "com.apple.Finder", float: true)

    #expect(rule.matches(bundleIdentifier: "com.apple.Finder"))
    #expect(!rule.matches(bundleIdentifier: "com.apple.Safari"))
}

@Test func ruleOptionallyMatchesTitleAndSubrole() {
    let rule = WindowRule(
        bundleIdentifier: "com.apple.Terminal",
        title: "ssh",
        subrole: "AXDialog",
        float: true
    )

    #expect(rule.matches(bundleIdentifier: "com.apple.Terminal", title: "ssh", subrole: "AXDialog"))
    #expect(!rule.matches(bundleIdentifier: "com.apple.Terminal", title: "local", subrole: "AXDialog"))
    #expect(!rule.matches(bundleIdentifier: "com.apple.Terminal", title: "ssh", subrole: "AXStandardWindow"))
}

@Test func parsesOptionalRuleMatchers() {
    let config = Config.parse("""
    [[rules]]
    title = "ssh"
    subrole = "AXDialog"
    float = true
    workspace = 2
    center = true
    width = 900
    height = 700
    bundle_id = "com.apple.Terminal"
    """)

    #expect(config?.rules == [WindowRule(bundleIdentifier: "com.apple.Terminal", title: "ssh", subrole: "AXDialog", float: true, workspace: 2, center: true, width: 900, height: 700)])
}
