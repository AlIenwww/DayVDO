import SwiftUI
import UniformTypeIdentifiers

struct ProjectTaskDropDelegate: DropDelegate {
    var accepts: () -> Bool
    var enter: () -> Void
    var commit: () -> Bool

    func validateDrop(info: DropInfo) -> Bool { accepts() && info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { if accepts() { enter() } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: accepts() ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool { accepts() && commit() }
}
