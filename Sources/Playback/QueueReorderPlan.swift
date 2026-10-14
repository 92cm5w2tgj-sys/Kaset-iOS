import Foundation

/// How to realise "move this Up Next entry here" with the only two queue primitives the page
/// offers: *Play next* (inserts right after the current track) and *Add to queue* (appends).
///
/// Either the front of Up Next is rewritten (cost: everything up to the furthest of the two
/// positions) or its tail is (cost: everything from the nearer of the two positions). The
/// cheaper side is chosen, so moves near the top or near the bottom stay short.
struct QueueReorderPlan: Equatable {
    enum Mode: Equatable {
        /// Re-insert with *Play next*, in reverse, so the last insert ends first.
        case front
        /// Re-insert with *Add to queue*, in order.
        case end
    }

    let mode: Mode
    /// Positions in the page queue to remove, highest first.
    let removeIndices: [Int]
    /// Video ids to re-insert, in the order they must be issued.
    let insertions: [String]

    var operationCount: Int { self.removeIndices.count + self.insertions.count }

    /// - Parameters:
    ///   - ids: video ids of the whole page queue.
    ///   - current: index of the current track in `ids`.
    ///   - source / destination: positions in `ids`, both after `current`.
    static func make(ids: [String], current: Int, source: Int, destination: Int) -> QueueReorderPlan? {
        guard source > current, destination > current, source != destination,
              source < ids.count, destination < ids.count
        else { return nil }

        let first = current + 1
        let upNext = Array(ids[first...])
        let a = source - first
        let b = destination - first
        var reordered = upNext
        reordered.insert(reordered.remove(at: a), at: b)

        let count = upNext.count
        let frontCost = max(a, b) + 1
        let endCost = count - min(a, b)

        if frontCost <= endCost {
            let hi = max(a, b)
            return QueueReorderPlan(
                mode: .front,
                removeIndices: Array(stride(from: first + hi, through: first, by: -1)),
                insertions: Array(reordered[0 ... hi].reversed())
            )
        }
        let lo = min(a, b)
        return QueueReorderPlan(
            mode: .end,
            removeIndices: Array(stride(from: first + count - 1, through: first + lo, by: -1)),
            insertions: Array(reordered[lo...])
        )
    }
}
