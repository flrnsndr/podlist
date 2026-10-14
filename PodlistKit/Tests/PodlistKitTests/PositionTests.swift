import Foundation
import Testing
@testable import PodlistKit

struct PositionTests {
    @Test func topAndBottomOfEmptyListStartAtZero() {
        #expect(Position.top(above: []) == 0)
        #expect(Position.bottom(below: []) == 0)
    }

    @Test func topBottomAndBetween() {
        let positions: [Double] = [0, 1, 2]
        #expect(Position.top(above: positions) == -1)
        #expect(Position.bottom(below: positions) == 3)
        #expect(Position.between(1, 2) == 1.5)
    }

    /// Applies `afterMove` and returns the original indices in the resulting order.
    private func order(_ positions: [Double], move offsets: IndexSet, to destination: Int) -> [Int] {
        var result = positions
        for (index, position) in Position.afterMove(positions, fromOffsets: offsets, toOffset: destination) {
            result[index] = position
        }
        return result.indices.sorted { result[$0] < result[$1] }
    }

    @Test(arguments: [
        // (offsets, destination, expected order) with SwiftUI onMove semantics
        ([0], 3, [1, 2, 0]),
        ([2], 0, [2, 0, 1]),
        ([0], 2, [1, 0, 2]),
        ([2], 1, [0, 2, 1]),
        ([0, 1], 3, [2, 0, 1]),
        ([0, 2], 1, [0, 2, 1]),
        ([1], 1, [0, 1, 2]),
    ])
    func moveKeepsSwiftUIOrder(offsets: [Int], destination: Int, expected: [Int]) {
        #expect(order([0, 1, 2], move: IndexSet(offsets), to: destination) == expected)
    }

    @Test func moveOnlyChangesMovedItems() {
        let changed = Position.afterMove([0, 1, 2, 3], fromOffsets: [3], toOffset: 1)
        #expect(changed == [3: 0.5])
    }

    @Test func moveWorksWithUnevenPositions() {
        #expect(order([-5, 0.25, 7], move: [0], to: 2) == [1, 0, 2])
        #expect(order([-5, 0.25, 7], move: [1, 2], to: 0) == [1, 2, 0])
    }
}
