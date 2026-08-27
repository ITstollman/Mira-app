import UIKit

/// Disk for the lookbook. JSON for the metadata, one JPEG per look beside it.
// ponytail: a single JSON blob rewritten in full on every save. Fine for hundreds of
// looks; move to SwiftData the day this needs querying, paging, or iCloud sync.
enum Vault {

    static func load() -> ([Look], Set<String>) {
        guard let data = try? Data(contentsOf: file),
              let snap = try? JSONDecoder().decode(Snap.self, from: data)
        else { return ([], []) }                                  // first launch or corrupt: start clean

        let byID = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, $0) })
        let looks: [Look] = snap.looks.compactMap { row in
            guard let g = byID[row.garment],                      // garment retired from the catalog: drop the look
                  let size = Size(rawValue: row.size) else { return nil }
            return Look(id: row.id, garment: g, size: size, shot: shot(row.id), date: row.date)
        }
        return (looks, Set(snap.loved))
    }

    static func save(_ looks: [Look], _ loved: Set<String>) {
        let snap = Snap(looks: looks.map { .init(id: $0.id, garment: $0.garment.id, size: $0.size.rawValue, date: $0.date) },
                        loved: Array(loved))
        let shots = looks.compactMap { l in l.shot.map { (l.id, $0) } }

        queue.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (id, img) in shots where !FileManager.default.fileExists(atPath: jpeg(id).path) {
                try? img.jpegData(compressionQuality: 0.85)?.write(to: jpeg(id), options: .atomic)
            }
            if let data = try? JSONEncoder().encode(snap) { try? data.write(to: file, options: .atomic) }
            sweep(keeping: Set(looks.map(\.id)))
        }
    }

    // MARK: -

    /// Codable mirror. The view models stay free of persistence; the garment travels as an id.
    private struct Snap: Codable {
        var looks: [Row]
        var loved: [String]
        struct Row: Codable { var id: UUID; var garment: String; var size: String; var date: Date }
    }

    private static let queue = DispatchQueue(label: "mira.vault")

    private static let dir: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mira", isDirectory: true)
    }()

    private static var file: URL { dir.appendingPathComponent("lookbook.json") }
    private static func jpeg(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).jpg") }
    private static func shot(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: jpeg(id).path) }

    /// Delete JPEGs no look points at any more.
    private static func sweep(keeping ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "jpg" {
            if let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent), !ids.contains(id) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}
