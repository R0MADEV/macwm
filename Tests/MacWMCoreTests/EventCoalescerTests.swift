import Testing
@testable import MacWMCore

@Test func coalescesAnEventUntilItIsConsumed() {
    var coalescer = EventCoalescer<String>()

    let first = coalescer.enqueue("refresh")
    let duplicate = coalescer.enqueue("refresh")
    let consumed = coalescer.consume("refresh")
    let empty = coalescer.consume("refresh")
    let afterConsume = coalescer.enqueue("refresh")
    #expect(first)
    #expect(!duplicate)
    #expect(consumed)
    #expect(!empty)
    #expect(afterConsume)
}

@Test func keepsDifferentEventsIndependent() {
    var coalescer = EventCoalescer<String>()

    let windows = coalescer.enqueue("windows")
    let screens = coalescer.enqueue("screens")
    let consumedWindows = coalescer.consume("windows")
    let consumedScreens = coalescer.consume("screens")
    #expect(windows)
    #expect(screens)
    #expect(consumedWindows)
    #expect(consumedScreens)
}
