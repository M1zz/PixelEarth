import Foundation

/// Top-down Nael. Every floor is its own map seen from above (0 is the village, 1...9 the floors below).
/// Floors are joined by stairs: going down is a walk, never a fall.
struct TDPoint: Codable, Equatable { var x: Int; var y: Int }
/// A drawn object standing on the map (tree, well, fence...). Its cells are blocked with Tile.propBlock (a tree's trunk with Tile.trunk).
struct TDProp: Codable { var kind: String; var x: Int; var y: Int
    var size: (w: Int, h: Int) { kind.hasPrefix("house") ? (9, 6) : (["well": (2, 2), "garden": (2, 2)][kind] ?? (1, 1)) }
}

final class TDMap: Codable {
    let floor: Int, w: Int, h: Int
    var tiles: [UInt8]
    var explored: [UInt8]
    var chests: [String: [ItemStack]] = [:]
    var up = TDPoint(x: 0, y: 0), down: TDPoint? = nil
    var buried: TDPoint? = nil          // grandmother's box: a chest appears when this dirt is dug
    var houses: [TDPoint] = []          // lamps of the errand houses (village only)
    var grandma = TDPoint(x: 0, y: 0)
    var props: [TDProp] = []
    // older saves have none of these, so they are optional
    var notes: [String: String]? = nil     // "x,y" of a chest -> the line found with it
    var flags: [String]? = nil             // one-time things already shown or done
    func has(_ f: String) -> Bool { flags?.contains(f) ?? false }
    func mark(_ f: String) { if !has(f) { flags = (flags ?? []) + [f] } }

    func place(_ kind: String, _ x: Int, _ y: Int) {
        let p = TDProp(kind: kind, x: x, y: y)
        for dy in 0..<p.size.h { for dx in 0..<p.size.w { set(x + dx, y + dy, kind == "tree" ? Tile.trunk : Tile.propBlock) } }
        props.append(p)
    }

    init(floor: Int, w: Int, h: Int, fill: Int) {
        self.floor = floor; self.w = w; self.h = h
        tiles = [UInt8](repeating: UInt8(fill), count: w * h); explored = [UInt8](repeating: 0, count: w * h)
    }
    @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h }
    @inline(__always) func get(_ x: Int, _ y: Int) -> Int { inside(x, y) ? Int(tiles[y * w + x]) : Tile.bedrock }
    @inline(__always) func set(_ x: Int, _ y: Int, _ t: Int) { if inside(x, y) { tiles[y * w + x] = UInt8(t) } }
    func blocks(_ x: Int, _ y: Int) -> Bool { TD.blocks(get(x, y)) }
    var openTiles: [TDPoint] { var o: [TDPoint] = []; for y in 0..<h { for x in 0..<w where !blocks(x, y) { o.append(TDPoint(x: x, y: y)) } }; return o }
}

enum TD {
    static let floors = 10
    /// What stands in the way when seen from above: walls, trees, water, and the things you use by facing them.
    static func blocks(_ t: Int) -> Bool {
        if TILES[t].solid { return true }
        return [Tile.propBlock, Tile.water, Tile.lava, Tile.trunk, Tile.pine, Tile.emptyLamp, Tile.lantern, Tile.lightSpring, Tile.throne, Tile.core, Tile.pedestal, Tile.tideWall].contains(t)
    }
    /// Walls that make the rock of a floor, by depth.
    static func rock(_ f: Int) -> Int { f >= 9 ? Tile.crystal : (f >= 8 ? Tile.ghostStone : Tile.stone) }

    static func generate(seed: UInt32) -> [TDMap] {
        var rng = LCG(state: seed &+ 7)
        return [village(&rng)] + (1...9).map { cave($0, &rng) }
    }

    // MARK: the village, floor 0

    static let houseSpots: [(x: Int, y: Int, blocked: Bool)] = [(26, 22, false), (12, 34, true), (70, 30, false)]

    static func village(_ rng: inout LCG) -> TDMap {
        let m = TDMap(floor: 0, w: 90, h: 60, fill: Tile.air)
        let plaza = TDPoint(x: 45, y: 34)
        // a ring of woods: bushes on the edge, trees in groves inside it
        for y in 0..<m.h { for x in 0..<m.w where min(x, y, m.w - 1 - x, m.h - 1 - y) < 3 { m.set(x, y, Tile.trunk) } }
        // dirt paths from the plaza to each door, and a road to the east
        func path(_ a: TDPoint, _ b: TDPoint) {
            var x = a.x, y = a.y
            while y != b.y { m.set(x, y, Tile.tdPath); m.set(x + 1, y, Tile.tdPath); y += b.y > y ? 1 : -1 }
            while x != b.x { m.set(x, y, Tile.tdPath); m.set(x, y + 1, Tile.tdPath); x += b.x > x ? 1 : -1 }
        }
        for y in (plaza.y - 3)...(plaza.y + 3) { for x in (plaza.x - 5)...(plaza.x + 5) { m.set(x, y, Tile.tdPath) } }
        for h in houseSpots { path(TDPoint(x: h.x, y: h.y + 3), plaza) }
        path(TDPoint(x: plaza.x + 5, y: plaza.y), TDPoint(x: 86, y: plaza.y))
        // a pond in the west, a smaller one in the north-east
        for (cx, cy, r) in [(18, 48, 4.5), (76, 11, 3.2)] { for y in 0..<m.h { for x in 0..<m.w where hypot(Double(x - cx), Double(y - cy) * 1.2) < r { m.set(x, y, Tile.water) } } }
        buildHouses(m)
        // the plaza: grandmother's well, a signpost, lanterns along the paths, a fenced garden
        m.place("well", plaza.x + 2, plaza.y - 2)
        m.place("sign", plaza.x - 6, plaza.y + 1)
        for p in [TDPoint(x: plaza.x - 6, y: plaza.y - 4), TDPoint(x: plaza.x + 6, y: plaza.y + 4), TDPoint(x: 28, y: 27), TDPoint(x: 66, y: 34)] { m.place("lantern", p.x, p.y) }
        m.place("garden", 54, 42); m.place("garden", 57, 42)
        for x in 53...60 { m.place("fence", x, 45) }
        // groves of trees and beds of flowers, in clusters with open meadow between
        for (cx, cy) in [(10, 12), (34, 50), (62, 52), (80, 46), (58, 14), (36, 9)] {
            for _ in 0..<7 {
                let x = cx + Int(rng.next() * 9) - 4, y = cy + Int(rng.next() * 7) - 3
                if m.get(x, y) == Tile.air && m.get(x, y + 1) == Tile.air && abs(x - plaza.x) + abs(y - plaza.y) > 9 { m.place("tree", x, y) }
            }
        }
        for (cx, cy) in [(30, 40), (52, 24), (70, 44), (20, 22)] {
            for _ in 0..<10 { let x = cx + Int(rng.next() * 6) - 3, y = cy + Int(rng.next() * 4) - 2; if m.get(x, y) == Tile.air { m.set(x, y, Tile.flower) } }
        }
        // grandmother's box, under a mound of soft earth
        let b = TDPoint(x: 36, y: 40); m.set(b.x, b.y, Tile.dirt); m.buried = b
        m.chests["\(b.x),\(b.y)"] = [ItemStack(id: Tile.greenSpore, n: 2), ItemStack(id: Tile.torch, n: 4)]
        m.up = plaza; m.grandma = TDPoint(x: plaza.x - 2, y: plaza.y - 1)
        return m
    }

    /// The three houses, seen from outside like any 2.5D town: a solid building with the errand's empty lamp at the door.
    /// The stuck house has a mound of earth before its door that has to be dug away.
    static func buildHouses(_ m: TDMap) {
        m.props.removeAll { $0.kind.hasPrefix("house") }
        m.houses = []
        for (i, h) in houseSpots.enumerated() {
            for y in (h.y - 3)...(h.y + 2) { for x in (h.x - 4)...(h.x + 4) where m.get(x, y) != Tile.lantern { m.set(x, y, Tile.air) } }
            let lamp = TDPoint(x: h.x, y: h.y + 2), wasLit = m.get(lamp.x, lamp.y) == Tile.lantern
            m.place("house\(i)", h.x - 4, h.y - 3)
            m.set(lamp.x, lamp.y, wasLit ? Tile.lantern : Tile.emptyLamp)
            if h.blocked && !wasLit { m.set(h.x, h.y + 3, Tile.dirt) }
            m.houses.append(lamp)
        }
    }

    /// Saves from before the houses stood: rebuild them, keeping which lamps were already lit.
    static func migrateHouses(_ m: TDMap) {
        guard m.floor == 0, !m.props.contains(where: { $0.kind.hasPrefix("house") }) else { return }
        let lit = m.houses.map { m.get($0.x, $0.y) == Tile.lantern }
        buildHouses(m)
        for (i, l) in lit.enumerated() where l && i < m.houses.count { m.set(m.houses[i].x, m.houses[i].y, Tile.lantern); m.set(houseSpots[i].x, houseSpots[i].y + 3, Tile.tdPath) }
    }

    // MARK: the floors, 1...9

    static func cave(_ f: Int, _ rng: inout LCG) -> TDMap {
        let m = TDMap(floor: f, w: 80, h: 60, fill: rock(f))
        var open = [Bool](repeating: false, count: m.w * m.h)
        for y in 2..<(m.h - 2) { for x in 2..<(m.w - 2) { open[y * m.w + x] = rng.next() < 0.43 } }
        for _ in 0..<5 {
            var next = open
            for y in 2..<(m.h - 2) { for x in 2..<(m.w - 2) {
                var walls = 0
                for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) && !open[(y + dy) * m.w + x + dx] { walls += 1 } }
                next[y * m.w + x] = walls < 5
            } }
            open = next
        }
        // keep the largest cave; the rest stays rock
        var region = [Int](repeating: -1, count: m.w * m.h), sizes: [Int] = []
        for i in 0..<open.count where open[i] && region[i] < 0 {
            var q = [i]; region[i] = sizes.count; var n = 0
            while let k = q.popLast() {
                n += 1
                for d in [-1, 1, -m.w, m.w] { let j = k + d; if j >= 0 && j < open.count && open[j] && region[j] < 0 { region[j] = sizes.count; q.append(j) } }
            }
            sizes.append(n)
        }
        let main = sizes.indices.max { sizes[$0] < sizes[$1] } ?? 0
        for i in 0..<open.count where open[i] && region[i] == main { m.tiles[i] = UInt8(Tile.air) }
        for x in 0..<m.w { m.set(x, 0, Tile.bedrock); m.set(x, m.h - 1, Tile.bedrock) }
        for y in 0..<m.h { m.set(0, y, Tile.bedrock); m.set(m.w - 1, y, Tile.bedrock) }

        let cells = m.openTiles
        let up = cells[Int(rng.next() * Double(cells.count)) % cells.count]
        m.up = up
        // stairs down: the open tile farthest from the stairs up
        let dist = bfs(m, from: up)
        var far = up, best = -1
        for p in cells where dist[p.y * m.w + p.x] > best { best = dist[p.y * m.w + p.x]; far = p }
        if f < 9 { m.down = far }

        // walls: hard rock deep inside; soft earth and ore come in patches and veins, not specks
        let nz = Noise(seed: UInt32(f) &* 977 &+ UInt32(rng.next() * 9999))
        for y in 1..<(m.h - 1) { for x in 1..<(m.w - 1) where m.get(x, y) == rock(f) {
            var nearOpen = false
            for dy in -1...1 { for dx in -1...1 where !m.blocks(x + dx, y + dy) { nearOpen = true } }
            if !nearOpen { if nz.noise2(Double(x) / 7 + 40, Double(y) / 7) > 0.55 { m.set(x, y, Tile.hardRock) }; continue }
            if nz.noise2(Double(x) / 6, Double(y) / 6) > 0.66 { m.set(x, y, Tile.dirt) }
            else if nz.noise2(Double(x) / 3 + 200, Double(y) / 3) > 0.78 - Double(f) * 0.006 { m.set(x, y, ore(f, &rng)) }
        } }
        // dressing in clumps: a few gardens of spores or mushrooms, and a pool of water or lava where the floor has one
        let clumpTile: Int = [5: Tile.greenSpore, 6: Tile.redSpore, 7: Tile.blueSpore, 8: Tile.shroom][f] ?? Tile.shroom
        let far2: (TDPoint) -> Bool = { p in abs(p.x - up.x) + abs(p.y - up.y) > 5 && (m.down.map { abs(p.x - $0.x) + abs(p.y - $0.y) > 5 } ?? true) }
        for c in cells.shuffledLCG(&rng).filter(far2).prefix(5) {
            for dy in -2...2 { for dx in -2...2 where m.get(c.x + dx, c.y + dy) == Tile.air && rng.next() < 0.45 { m.set(c.x + dx, c.y + dy, clumpTile) } }
        }
        if f == 6 || f == 7, let c = cells.shuffledLCG(&rng).first(where: far2) {
            for dy in -3...3 { for dx in -4...4 where hypot(Double(dx), Double(dy) * 1.3) < 3.4 && m.get(c.x + dx, c.y + dy) == Tile.air { m.set(c.x + dx, c.y + dy, f == 6 ? Tile.lava : Tile.water) } }
        }
        // light springs and chests, against walls
        var springs = 0, chests = 0
        for p in cells.shuffledLCG(&rng) {
            guard m.get(p.x, p.y) == Tile.air, abs(p.x - up.x) + abs(p.y - up.y) > 5 else { continue }
            let walls = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { m.blocks(p.x + $0.0, p.y + $0.1) }.count
            if walls == 3 && chests < 3 { m.set(p.x, p.y, Tile.chest); m.chests["\(p.x),\(p.y)"] = loot(f, &rng); chests += 1 }
            else if walls >= 1 && springs < 4 && rng.next() < 0.05 { m.set(p.x, p.y, Tile.lightSpring); springs += 1 }
            if springs >= 4 && chests >= 3 { break }
        }
        // the pickaxe waits on the first floor, a step from the stairs
        if f == 1 {
            let p = [(2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (-1, -1)].map { TDPoint(x: up.x + $0.0, y: up.y + $0.1) }.first { m.get($0.x, $0.y) == Tile.air } ?? TDPoint(x: up.x + 1, y: up.y)
            m.set(p.x, p.y, Tile.chest); m.chests["\(p.x),\(p.y)"] = [ItemStack(id: Item.woodPick, n: 1), ItemStack(id: Tile.torch, n: 6)]
        }
        // from floor 5 the way down is sealed by cracked rock: a pickaxe opens it
        if f >= 5, let d = m.down { for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) && !m.blocks(d.x + dx, d.y + dy) { m.set(d.x + dx, d.y + dy, Tile.crack) } } }
        // the throne of floors 5...9 stands midway, in a cleared hall
        if f >= 5 {
            let inner = cells.filter { $0.x >= 7 && $0.x < m.w - 7 && $0.y >= 7 && $0.y < m.h - 6 && dist[$0.y * m.w + $0.x] >= 0 }
            let mid = inner.min { abs(dist[$0.y * m.w + $0.x] - best / 2) < abs(dist[$1.y * m.w + $1.x] - best / 2) } ?? up
            for y in (mid.y - 3)...(mid.y + 3) { for x in (mid.x - 4)...(mid.x + 4) where m.inside(x, y) && x > 0 && y > 0 && x < m.w - 1 && y < m.h - 1 { m.set(x, y, Tile.air) } }
            m.set(mid.x, mid.y - 3, Tile.throne)
        }
        if f == 9 { m.set(far.x, far.y, Tile.core) }
        if let d = m.down { m.set(d.x, d.y, Tile.stairsDown) }
        m.set(up.x, up.y, Tile.stairsUp)
        buildCamp(m)
        dress(m)
        return m
    }

    // MARK: the camp on floor 5

    /// A clearing a few steps from the stairs on floor 5: a fire nobody let go out, three altars to wake with the jar's
    /// colours, and a tent by each. Creatures keep away from the fire.
    static func buildCamp(_ m: TDMap) {
        guard m.floor == 5, !m.has("camp") else { return }
        m.mark("camp")
        let dist = bfs(m, from: m.up)
        let c0 = m.openTiles.first { dist[$0.y * m.w + $0.x] == 5 } ?? m.up
        let c = TDPoint(x: min(max(c0.x, 8), m.w - 9), y: min(max(c0.y, 8), m.h - 9))
        let keep: Set<Int> = [Tile.stairsUp, Tile.stairsDown, Tile.chest, Tile.throne, Tile.lightSpring, Tile.bedrock, Tile.crack, Tile.core]
        for y in (c.y - 5)...(c.y + 5) { for x in (c.x - 6)...(c.x + 6) where hypot(Double(x - c.x), Double(y - c.y) * 1.15) < 5.6 {
            if keep.contains(m.get(x, y)) || m.props.contains(where: { $0.x == x && $0.y == y }) { continue }
            m.set(x, y, Tile.air)
        } }
        m.place("campfire", c.x, c.y)
        for (k, dx, dy) in [("altarR", -3, -2), ("altarG", 0, -3), ("altarB", 3, -2), ("tentR", -4, 2), ("tentG", 0, 3), ("tentB", 4, 2)] where m.get(c.x + dx, c.y + dy) == Tile.air {
            m.place(k, c.x + dx, c.y + dy)
        }
    }

    // MARK: grandmother's old way and the clues of a floor

    /// Lays, once per floor: the old torches grandmother left and the spot where she rested, and a few clues
    /// (light leaking from a wall, a dropped tool, a sound behind rock, a hollow wall) each with something behind it.
    /// Deterministic from the floor number, so older saves get the same when they load.
    static func dress(_ m: TDMap) {
        defer { dressStory(m) }
        guard m.floor > 0, !(m.has("dressed") && m.has("gates")) else { return }
        let fresh = !m.has("dressed")
        m.mark("dressed"); m.mark("gates")
        let f = m.floor
        var rng = LCG(state: UInt32(f) &* 2654435761 &+ 977)
        var notes = m.notes ?? [:]
        let dist = bfs(m, from: m.up)
        var best = 0; for d in dist where d > best { best = d }
        func d(_ p: TDPoint) -> Int { dist[p.y * m.w + p.x] }
        func open(_ p: TDPoint) -> Bool { m.get(p.x, p.y) == Tile.air }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

        // grandmother's resting spot: a dead end about halfway down (on floor 9, by the warehouse at the far end)
        if fresh {
        let ends = m.openTiles.filter { p in open(p) && d(p) > 0 && dirs.filter { m.blocks(p.x + $0.0, p.y + $0.1) }.count == 3 }
        let want = f == 9 ? best * 9 / 10 : best / 2
        if let c = ends.min(by: { abs(d($0) - want) < abs(d($1) - want) }) {
            m.set(c.x, c.y, Tile.chest)
            m.chests["\(c.x),\(c.y)"] = [ItemStack(id: Tile.torch, n: 4), ItemStack(id: Item.potion, n: 1), ItemStack(id: [Tile.greenSpore, Tile.redSpore, Tile.blueSpore][f % 3], n: 1)]
            notes["\(c.x),\(c.y)"] = "td.cache.\(f)"
            // her torches: from near the stairs up to the spot, then on toward the stairs down, sparser
            for (i, p) in path(m, from: m.up, to: c).enumerated() where i >= 8 && i % 11 == 8 && open(p) { m.props.append(TDProp(kind: "oldTorch", x: p.x, y: p.y)) }
            if f < 9, let dn = m.down { for (i, p) in path(m, from: c, to: dn).enumerated() where i >= 7 && i % 15 == 7 && open(p) { m.props.append(TDProp(kind: "oldTorch", x: p.x, y: p.y)) } }
        }
        }

        // a little room in the rock behind one wall tile, reached from an open tile in front of it
        var used: [TDPoint] = []
        func room(_ minFrac: Double, _ maxFrac: Double) -> (front: TDPoint, door: TDPoint, mid: TDPoint)? {
            // the wanted stretch of the floor first, then anywhere, so every floor gets its clues
            if let r = tryRoom(minFrac, maxFrac) { return r }
            return tryRoom(0.08, 1.01)
        }
        func tryRoom(_ minFrac: Double, _ maxFrac: Double) -> (front: TDPoint, door: TDPoint, mid: TDPoint)? {
            for o in m.openTiles.shuffledLCG(&rng) where open(o) && d(o) > Int(Double(best) * minFrac) && d(o) < Int(Double(best) * maxFrac) {
                if used.contains(where: { abs($0.x - o.x) + abs($0.y - o.y) < 9 }) { continue }
                for (dx, dy) in dirs.shuffledLCG(&rng) { for depth in 3...6 {
                    // a short tunnel of soft earth (depth - 2 tiles) leads from the wall into the room
                    let door = TDPoint(x: o.x + dx, y: o.y + dy), mid = TDPoint(x: o.x + dx * depth, y: o.y + dy * depth)
                    guard mid.x > 3, mid.y > 3, mid.x < m.w - 4, mid.y < m.h - 4 else { continue }
                    func rockAt(_ x: Int, _ y: Int) -> Bool { let t = m.get(x, y); return TILES[t].solid && t != Tile.bedrock && t != Tile.crack }
                    var ok = true
                    for y in (mid.y - 2)...(mid.y + 2) { for x in (mid.x - 2)...(mid.x + 2) where ok && !rockAt(x, y) { ok = false } }
                    for i in 1...(depth - 2) where ok {
                        let tx = o.x + dx * i, ty = o.y + dy * i
                        if !rockAt(tx, ty) || !rockAt(tx + dy, ty + dx) || !rockAt(tx - dy, ty - dx) { ok = false }
                    }
                    guard ok else { continue }
                    for y in (mid.y - 1)...(mid.y + 1) { for x in (mid.x - 1)...(mid.x + 1) { m.set(x, y, Tile.air) } }
                    for i in 2..<max(2, depth - 1) { m.set(o.x + dx * i, o.y + dy * i, Tile.dirt) }
                    used.append(o)
                    return (o, door, mid)
                } }
            }
            return nil
        }
        func stash(_ p: TDPoint, rare: Double) {
            m.set(p.x, p.y, Tile.chest)
            let r = rng.next()
            if r < rare {                                     // the jackpot: a spore that turns the jar, and a shard
                m.chests["\(p.x),\(p.y)"] = [ItemStack(id: [Tile.greenSpore, Tile.redSpore, Tile.blueSpore][rng.int(3)], n: 3), ItemStack(id: Item.lightShard, n: 1)]
                notes["\(p.x),\(p.y)"] = "td.lore.rare"
            } else if r < rare + 0.3 {                         // only a few words from before the dark, and a little light
                m.chests["\(p.x),\(p.y)"] = [ItemStack(id: Tile.torch, n: 2)]
                notes["\(p.x),\(p.y)"] = "td.lore.\(rng.int(8))"
            } else { m.chests["\(p.x),\(p.y)"] = loot(f, &rng) }
        }
        if fresh {
        // seen: light seeping through a thin wall of earth, from a spring inside
        if let r = room(0.15, 0.6) {
            m.set(r.door.x, r.door.y, Tile.dirt); m.set(r.mid.x, r.mid.y, Tile.lightSpring)
            stash(TDPoint(x: r.mid.x + 1, y: r.mid.y + 1), rare: 0.2)
        }
        // seen: a dropped pickaxe on the floor, its handle pointing at soft earth
        if let r = room(0.2, 0.8) {
            m.set(r.door.x, r.door.y, Tile.dirt)
            let k = r.door.x > r.front.x ? 2 : (r.door.x < r.front.x ? 1 : (r.door.y > r.front.y ? 0 : 3))
            m.props.append(TDProp(kind: "clueTool\(k)", x: r.front.x, y: r.front.y))
            stash(r.mid, rare: 0.15)
        }
        // guessed: water dripping somewhere behind the rock
        if let r = room(0.3, 0.9) {
            m.set(r.door.x, r.door.y, Tile.dirt); m.set(r.mid.x - 1, r.mid.y - 1, Tile.water); m.set(r.mid.x, r.mid.y - 1, Tile.water)
            m.props.append(TDProp(kind: "clueSound", x: r.front.x, y: r.front.y))
            stash(TDPoint(x: r.mid.x, y: r.mid.y + 1), rare: 0.2)
        }
        // hidden: a wall like any other, that sounds hollow when struck
        if let r = room(0.25, 0.95) {
            m.set(r.door.x, r.door.y, Tile.stone)
            m.props.append(TDProp(kind: "hollow", x: r.door.x, y: r.door.y))
            stash(r.mid, rare: 0.35)
        }
        }
        // walls that open to a colour of the jar's light: roots to green, hard rock cracks to red, water parts to blue,
        // and a darkness that gives way only when the jar is covered. Some wait on upper floors for a colour found later.
        let gateKinds: [Int: [String]] = [1: ["G"], 2: ["R", "G"], 3: ["B", "R"], 4: ["C", "B"], 5: ["G", "R"], 6: ["R", "B"], 7: ["B", "C"], 8: ["C", "R"], 9: ["G", "B"]]
        for k in gateKinds[f] ?? [] {
            guard let r = room(0.2, 0.95) else { continue }
            m.set(r.door.x, r.door.y, k == "B" ? Tile.water : Tile.hardRock)
            m.props.append(TDProp(kind: "gate\(k)", x: r.door.x, y: r.door.y))
            stash(r.mid, rare: 0.5)
        }
        m.notes = notes
    }

    /// Rumors and truths. Floors 1...4 carry scratched rumors about the lords below; floors 5...9 hide three things
    /// the lord left behind, each one line of who they really are. Placed once, after the clues.
    static func dressStory(_ m: TDMap) {
        let f = m.floor
        guard f > 0, !m.has("story") else { return }
        m.mark("story")
        var rng = LCG(state: UInt32(f) &* 40503 &+ 31337)
        let dist = bfs(m, from: m.up)
        var best = 0; for d in dist where d > best { best = d }
        let taken = m.props.map { TDPoint(x: $0.x, y: $0.y) } + [m.up] + (m.down.map { [$0] } ?? [])
        func far(_ p: TDPoint, _ others: [TDPoint], _ r: Int) -> Bool { !others.contains { abs($0.x - p.x) + abs($0.y - p.y) < r } }
        if f <= 4 {
            // a rumor scratched on a wall that faces open ground; the fourth floor, the road of rumors, has two
            let lords = f == 4 ? [8, 9] : [f + 4]
            var placed: [TDPoint] = []
            for lord in lords {
                for p in m.openTiles.shuffledLCG(&rng) where m.get(p.x, p.y) == Tile.air && dist[p.y * m.w + p.x] > best / 5 && far(p, taken + placed, 10) {
                    let w = TDPoint(x: p.x, y: p.y - 1)                         // the wall just north, so it reads as a wall face
                    guard TILES[m.get(w.x, w.y)].solid, m.get(w.x, w.y) != Tile.bedrock else { continue }
                    m.props.append(TDProp(kind: "graffiti\(lord)", x: w.x, y: w.y)); placed.append(p); break
                }
            }
            return
        }
        // three truths: early, midway and far, at quiet corners of the floor
        let corners = m.openTiles.filter { p in m.get(p.x, p.y) == Tile.air && [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { m.blocks(p.x + $0.0, p.y + $0.1) }.count >= 2 && dist[p.y * m.w + p.x] > 0 }
        var placed: [TDPoint] = []
        for (i, frac) in [0.3, 0.6, 0.9].enumerated() {
            let want = Int(Double(best) * frac)
            let pool = corners.filter { far($0, taken + placed, 8) }.sorted { abs(dist[$0.y * m.w + $0.x] - want) < abs(dist[$1.y * m.w + $1.x] - want) }
            guard let p = Array(pool.prefix(6)).shuffledLCG(&rng).first else { continue }
            m.place("truth\(i)", p.x, p.y); placed.append(p)
        }
    }

    /// The way between two points, step by step (empty when there is none).
    static func path(_ m: TDMap, from a: TDPoint, to b: TDPoint) -> [TDPoint] {
        let d = bfs(m, from: b)
        guard d[a.y * m.w + a.x] >= 0 else { return [] }
        var p = a, out: [TDPoint] = []
        while d[p.y * m.w + p.x] > 0 && out.count < 2000 {
            out.append(p)
            let cur = d[p.y * m.w + p.x]
            guard let n = [(1, 0), (-1, 0), (0, 1), (0, -1)].map({ TDPoint(x: p.x + $0.0, y: p.y + $0.1) }).first(where: { m.inside($0.x, $0.y) && d[$0.y * m.w + $0.x] == cur - 1 }) else { break }
            p = n
        }
        return out
    }

    static func oreChance(_ f: Int) -> Double { 0.05 + Double(f) * 0.006 }
    static func ore(_ f: Int, _ rng: inout LCG) -> Int {
        let r = rng.next()
        if f >= 7 && r < 0.25 { return Tile.diamondOre }
        if f >= 4 && r < 0.5 { return Tile.gold }
        if r < 0.75 { return Tile.iron }
        return Tile.coal
    }
    static func loot(_ f: Int, _ rng: inout LCG) -> [ItemStack] {
        var l = [ItemStack(id: Item.potion, n: 1 + Int(rng.next() * 2)), ItemStack(id: Tile.torch, n: 4)]
        l.append(ItemStack(id: [Tile.greenSpore, Tile.redSpore, Tile.blueSpore][Int(rng.next() * 3) % 3], n: 1 + Int(rng.next() * 2)))
        if f >= 4 && rng.next() < 0.5 { l.append(ItemStack(id: Item.diamond, n: 1)) }
        if rng.next() < 0.25 { l.append(ItemStack(id: Item.lightShard, n: 1)) }
        return l
    }

    /// Steps from a point to every open tile (-1 where unreachable).
    static func bfs(_ m: TDMap, from s: TDPoint) -> [Int] {
        var d = [Int](repeating: -1, count: m.w * m.h); var q = [s]; var head = 0
        d[s.y * m.w + s.x] = 0
        while head < q.count {
            let p = q[head]; head += 1
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TDPoint(x: p.x + dx, y: p.y + dy)
                guard m.inside(n.x, n.y), d[n.y * m.w + n.x] < 0, !m.blocks(n.x, n.y) || m.get(n.x, n.y) == Tile.chest else { continue }
                d[n.y * m.w + n.x] = d[p.y * m.w + p.x] + 1; q.append(n)
            }
        }
        return d
    }
}

extension Array {
    func shuffledLCG(_ rng: inout LCG) -> [Element] {
        var a = self
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(rng.next() * Double(i + 1)) % (i + 1)) }
        return a
    }
}
