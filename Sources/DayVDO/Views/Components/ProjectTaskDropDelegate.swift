import SwiftUI
import UniformTypeIdentifiers

struct ProjectTaskDropDelegate: DropDelegate {
    var accepts: () -> Bool
    var enter: () -> Void
    var exit: () -> Void = {}
    var commit: () -> Bool

    func validateDrop(info: DropInfo) -> Bool { accepts() && info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { if accepts() { enter() } }
    func dropExited(info: DropInfo) { exit() }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let accepted = accepts()
        if accepted { enter() }
        return DropProposal(operation: accepted ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool { accepts() && commit() }
}
