import Testing
@testable import MacWMCore

@Test func growKeepsCenterAndIncreasesFrame() {
    let frame = Frame(x: 100, y: 100, width: 400, height: 300)

    let resized = frame.resized(operation: .grow, amount: 40)

    #expect(resized == Frame(x: 80, y: 80, width: 440, height: 340))
}

@Test func shrinkStopsAtMinimumSize() {
    let frame = Frame(x: 100, y: 100, width: 100, height: 80)

    let resized = frame.resized(operation: .shrink, amount: 80, minimumSize: (120, 100))

    #expect(resized == Frame(x: 90, y: 90, width: 120, height: 100))
}
