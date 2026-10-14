import Testing

@testable import KasetiOS

struct QueueReorderPlanTests {
    // ids: current = "c", then Up Next "a" "b" "d" "e" "f" "g" (positions 1...6)
    private let ids = ["c", "a", "b", "d", "e", "f", "g"]

    @Test func movingNearTheTopRewritesTheFront() throws {
        let plan = try #require(QueueReorderPlan.make(ids: ids, current: 0, source: 3, destination: 1))
        #expect(plan.mode == .front)
        #expect(plan.removeIndices == [3, 2, 1])
        // new Up Next prefix is [d, a, b]; inserted in reverse so d ends first
        #expect(plan.insertions == ["b", "a", "d"])
    }

    @Test func movingNearTheBottomRewritesTheTail() throws {
        let plan = try #require(QueueReorderPlan.make(ids: ids, current: 0, source: 5, destination: 6))
        #expect(plan.mode == .end)
        #expect(plan.removeIndices == [6, 5])
        #expect(plan.insertions == ["g", "f"])
    }

    @Test func movingDownTheListPicksTheCheaperSide() throws {
        // a (position 1) to position 6: front would rewrite 6, tail also 6 -> front on ties
        let plan = try #require(QueueReorderPlan.make(ids: ids, current: 0, source: 1, destination: 6))
        #expect(plan.operationCount == 12)
        #expect(plan.mode == .front)
    }

    @Test func rejectsCurrentOrNoOpMoves() {
        #expect(QueueReorderPlan.make(ids: ids, current: 0, source: 0, destination: 2) == nil)
        #expect(QueueReorderPlan.make(ids: ids, current: 0, source: 2, destination: 2) == nil)
        #expect(QueueReorderPlan.make(ids: ids, current: 2, source: 1, destination: 4) == nil)
    }

    @Test func resultingOrderMatchesTheRequest() throws {
        // Apply the plan to a model of the page queue and check the final order.
        for source in 1 ... 6 {
            for destination in 1 ... 6 where destination != source {
                let plan = try #require(QueueReorderPlan.make(ids: ids, current: 0, source: source, destination: destination))
                var queue = ids
                for index in plan.removeIndices { queue.remove(at: index) }
                for id in plan.insertions {
                    switch plan.mode {
                    case .front: queue.insert(id, at: 1)
                    case .end: queue.append(id)
                    }
                }
                var expected = ids
                expected.insert(expected.remove(at: source), at: destination)
                #expect(queue == expected, "move \(source)->\(destination)")
            }
        }
    }
}
