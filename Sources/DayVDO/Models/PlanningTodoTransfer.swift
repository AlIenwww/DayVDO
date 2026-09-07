import Foundation

/// A system URL representation also works in an unbundled Swift Package build.
/// These identifiers are drag payloads only; they are never opened as URLs.
enum PlanningTodoTransfer {
    static func url(for id: UUID) -> URL {
        URL(string: "dayvdo-planning://todo/\(id.uuidString)")!
    }

    static func id(from url: URL) -> UUID? {
        guard url.scheme == "dayvdo-planning", url.host == "todo",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    static func provider(for id: UUID) -> NSItemProvider {
        NSItemProvider(object: url(for: id) as NSURL)
    }

    static func loadID(from provider: NSItemProvider, completion: @escaping @Sendable (UUID?) -> Void) {
        provider.loadObject(ofClass: NSURL.self) { value, _ in
            completion((value as? URL).flatMap { id(from: $0) })
        }
    }
}
