import UIKit

/// Disk for the lookbook. JSON for the metadata, one JPEG per look beside it, and an
/// MP4 beside that for the ones you filmed.
// ponytail: a single JSON blob rewritten in full on every save. Fine for hundreds of
// looks; move to SwiftData the day this needs querying, paging, or iCloud sync.
enum Vault {

    static func load() -> ([Look], Set<String>) {
        guard let data = try? Data(contentsOf: file),
              let snap = try? JSONDecoder().decode(Snap.self, from: data)
        else { return ([], []) }                                  // first launch or corrupt: start clean

        let byID = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, $0) })
        let looks: [Look] = snap.looks.compactMap { row in
            guard let size = Size(rawValue: row.size) else { return nil }
            // A house piece travels as an id. Anything you brought in — a link, a photo,
            // a sentence — is not in the catalog and used to take its looks down with it
            // on the next launch, jpeg and all. Those carry their own description now.
            guard let g = byID[row.garment] ?? row.piece?.garment(id: row.garment,
                                                                  shot: try? Data(contentsOf: ref(row.garment)))
            else { return nil }
            return Look(id: row.id, garment: g, size: size,
                        shot: shot(row.id), film: film(row.id), date: row.date)
        }
        return (looks, Set(snap.loved))
    }

    static func save(_ looks: [Look], _ loved: Set<String>) {
        let snap = Snap(looks: looks.map {
            .init(id: $0.id, garment: $0.garment.id, size: $0.size.rawValue, date: $0.date,
                  piece: Piece($0.garment))
        }, loved: Array(loved))
        let shots = looks.compactMap { l in l.shot.map { (l.id, $0) } }
        let refs = looks.compactMap { l in l.garment.shot.map { (l.garment.id, $0) } }

        queue.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (id, img) in shots where !FileManager.default.fileExists(atPath: jpeg(id).path) {
                try? img.jpegData(compressionQuality: 0.85)?.write(to: jpeg(id), options: .atomic)
            }
            for (gid, data) in refs where !FileManager.default.fileExists(atPath: ref(gid).path) {
                try? data.write(to: ref(gid), options: .atomic)
            }
            if let data = try? JSONEncoder().encode(snap) { try? data.write(to: file, options: .atomic) }
            sweep(looks: Set(looks.map(\.id)), pieces: Set(looks.map(\.garment.id)))
        }
    }

    /// Takes a just-finished recording off the temporary directory and gives it a home
    /// under the look's id. Returns nil if it couldn't be moved, in which case there is
    /// no look worth keeping — the clip is the whole point of it.
    static func adopt(_ temp: URL, as id: UUID) -> URL? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let home = mp4(id)
        try? FileManager.default.removeItem(at: home)
        do { try FileManager.default.moveItem(at: temp, to: home) } catch { return nil }
        return home
    }

    // MARK: -

    /// Codable mirror. The view models stay free of persistence; a house garment travels
    /// as an id, and anything else carries enough of itself to be rebuilt.
    private struct Snap: Codable {
        var looks: [Row]
        var loved: [String]
        struct Row: Codable {
            var id: UUID; var garment: String; var size: String; var date: Date
            /// Absent for catalog pieces, and for rows written before this existed.
            var piece: Piece?
        }
    }

    /// Everything about a brought-in garment that isn't its photograph or its identity.
    // ponytail: no tint — every constructor that can make one of these passes M.petal.
    // Give scraped pieces a real colour and this needs an rgba array beside `cut`.
    private struct Piece: Codable {
        var name: String, brand: String, price: Int
        var cut: String, category: String, prompt: String
        var link: String?

        init?(_ g: Garment) {
            // Anything the catalog can hand back travels as an id. Everything else — a
            // link, a photo, a sentence, one of the starter outfits — carries itself, or
            // it does not come back at all. isMine missed the starter ten, and a look
            // kept in one used to vanish on the next launch, jpeg and all.
            guard !Catalog.ids.contains(g.id) else { return nil }
            name = g.name; brand = g.brand; price = g.price
            cut = g.cut.rawValue; category = g.category.rawValue
            prompt = g.prompt; link = g.link
        }

        func garment(id: String, shot: Data?) -> Garment {
            Garment(id: id, name: name, brand: brand, price: price,
                    cut: Garment.Cut(rawValue: cut) ?? .slip,
                    tint: M.petal,
                    category: Garment.Category(rawValue: category) ?? .dresses,
                    prompt: prompt, shot: shot, link: link)
        }
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
    private static func mp4(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).mp4") }
    private static func shot(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: jpeg(id).path) }
    private static func film(_ id: UUID) -> URL? {
        let url = mp4(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A garment id can be a url or a uuid, so it is scrubbed down to something a
    /// filesystem will take. Two ids that scrub to the same name would share a
    /// reference photo; they'd have to differ only in punctuation for that to happen.
    private static func ref(_ garment: String) -> URL {
        let safe = String(garment.map { $0.isLetter || $0.isNumber ? $0 : "-" }.suffix(80))
        return dir.appendingPathComponent("ref-\(safe).jpg")
    }

    /// Delete the stills, clips and reference shots nothing points at any more.
    private static func sweep(looks: Set<UUID>, pieces: Set<String>) {
        let keep = Set(pieces.map { ref($0).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files {
            // A clip is given its home before its look exists — the poster frame is still
            // being pulled out of it. A still saved in that gap would otherwise sweep the
            // recording away as an orphan, so nothing this young is touched.
            if let made = try? f.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(made) < 60 { continue }
            let name = f.deletingPathExtension().lastPathComponent
            switch f.pathExtension {
            case "jpg" where name.hasPrefix("ref-"):
                if !keep.contains(f.lastPathComponent) { try? FileManager.default.removeItem(at: f) }
            case "jpg", "mp4":
                if let id = UUID(uuidString: name), !looks.contains(id) {
                    try? FileManager.default.removeItem(at: f)
                }
            default: break
            }
        }
    }
}
