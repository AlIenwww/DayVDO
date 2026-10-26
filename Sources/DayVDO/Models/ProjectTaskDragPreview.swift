import Foundation

/// Hover changes only this transient order; persistence and undo happen once at drop.
struct ProjectTaskDragPreview: Equatable {
    let itemID: UUID
    let projectID: UUID
    var orderedIDs: [UUID]
    private(set) var lastTargetID: UUID?

    mutating func move(over targetID: UUID?) {
        if targetID == itemID {
            lastTargetID = nil
            return
        }
        guard targetID != lastTargetID || targetID == nil,
              let source = orderedIDs.firstIndex(of: itemID) else { return }
        if let targetID {
            guard let target = orderedIDs.firstIndex(of: targetID) else { return }
            orderedIDs.remove(at: source)
            orderedIDs.insert(itemID, at: target)
        } else {
            orderedIDs.remove(at: source)
            orderedIDs.append(itemID)
        }
        lastTargetID = targetID
    }

    var followingID: UUID? {
        guard let index = orderedIDs.firstIndex(of: itemID), index + 1 < orderedIDs.count else { return nil }
        return orderedIDs[index + 1]
    }
}
