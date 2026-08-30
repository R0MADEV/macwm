import Testing
@testable import MacWMCore

@Test func layoutSupportsAnyWindowCountWithoutOverlap() {
    for count in 1...12 {
        let windows = (1...count).map { WindowID(UInt64($0)) }
        let frames = BSPLayout.frames(
            for: windows,
            in: Frame(x: 0, y: 0, width: 1200, height: 800),
            outerGap: 16,
            innerGap: 8
        )

        #expect(frames.count == count)
        for frame in frames.values {
            #expect(frame.width > 0)
            #expect(frame.height > 0)
            #expect(frame.x >= 16)
            #expect(frame.y >= 16)
            #expect(frame.x + frame.width <= 1184)
            #expect(frame.y + frame.height <= 784)
        }

        let values = Array(frames.values)
        for index in values.indices {
            for otherIndex in values.indices where index < otherIndex {
                #expect(!overlaps(values[index], values[otherIndex]))
            }
        }
    }
}

private func overlaps(_ first: Frame, _ second: Frame) -> Bool {
    let horizontalOverlap = min(first.x + first.width, second.x + second.width) - max(first.x, second.x)
    let verticalOverlap = min(first.y + first.height, second.y + second.height) - max(first.y, second.y)
    return horizontalOverlap > 0 && verticalOverlap > 0
}
