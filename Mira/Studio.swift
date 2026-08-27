import SwiftUI

struct Look: Identifiable, Hashable {
    let id: UUID
    let garment: Garment
    let size: Size
    let shot: UIImage?
    let date: Date

    // defaults keep every Look(garment:size:shot:) call site as it was; Vault passes all five
    init(id: UUID = UUID(), garment: Garment, size: Size, shot: UIImage?, date: Date = Date()) {
        self.id = id; self.garment = garment; self.size = size; self.shot = shot; self.date = date
    }

    static func == (a: Look, b: Look) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@Observable final class Studio {
    var wearing: Garment? = Catalog.all.first
    var size: Size = .s
    var looks: [Look] = []
    var loved: Set<String> = []
    /// Pieces you brought in from a link. ponytail: in memory only — the server's shot
    /// expires after 30 minutes anyway, so these don't survive a relaunch.
    var mine: [Garment] = []
    /// Bumped on every pick, same piece or not. The mirror watches this rather than
    /// ``wearing`` so re-tapping what you already have on still starts a session.
    private(set) var picked = 0

    init() {
        (looks, loved) = Vault.load()
        if looks.isEmpty, Dev.has("dev:seed") {
            looks = Catalog.all.prefix(4).map { Look(garment: $0, size: .s, shot: nil) }
        }
    }

    /// A scraped piece lands at the front of your closet and goes straight on.
    func add(_ g: Garment) {
        mine.removeAll { $0.link == g.link }
        withAnimation(.spring) { mine.insert(g, at: 0) }
        wear(g)
    }

    func wear(_ g: Garment) {
        picked += 1
        guard wearing?.id != g.id else { return }
        tap()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { wearing = g }
    }

    func love(_ g: Garment) {
        tap(.medium)
        if loved.contains(g.id) { loved.remove(g.id) } else { loved.insert(g.id) }
        Vault.save(looks, loved)
    }

    func keep(_ look: Look) {
        guard !looks.contains(look) else { return }   // ponytail: reopening a kept look re-keeps as a no-op
        tap(.medium)
        withAnimation(.spring) { looks.insert(look, at: 0) }
        Vault.save(looks, loved)
    }
}
