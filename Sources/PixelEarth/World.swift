import Foundation

/// Deterministic hashing / value noise (same formulas across platforms so seeds are portable).
struct Noise {
    var seed: UInt32

    func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 374761393 &+ UInt32(truncatingIfNeeded: y) &* 668265263 &+ seed
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h) / 4294967296.0
    }
    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    func noise2(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = smooth(x - Double(xi)), fy = smooth(y - Double(yi))
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }
    func noise1(_ x: Double) -> Double { noise2(x, 7.31) }
}

/// Small LCG so world generation is reproducible from a seed.
struct LCG {
    var state: UInt32
    mutating func next() -> Double {
        state = state &* 1664525 &+ 1013904223
        return Double(state) / 4294967296.0
    }
    mutating func int(_ n: Int) -> Int { Int(next() * Double(n)) }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + int(hi - lo) }
}

final class World {
    static let W = 640, H = 280
    let w = World.W, h = World.H
    var tiles: [UInt8]
    var surface: [Int]
    var biome: [UInt8]      // 0 forest, 1 snow, 2 desert
    var explored: [UInt8]
    var chests: [String: [ItemStack]] = [:]
    /// Story geometry
    var campX = World.W / 2
    var shaftX = World.W / 2 + 34
    var shaftTiles: [(x: Int, y: Int)] = []          // dug open when the disaster strikes
    var pedestals: [(x: Int, y: Int)] = []
    var throneCol: [String: Int] = [:]               // "x,y" -> atlas column: 0 empty, 1 a lord, 2 the player
    var pedestalState: [String: Int] = [:]           // "x,y" -> 0 unlit, 1 red, 2 green, 3 blue
    var coreX = World.W / 2, coreY = Layers.cityTop + 9
    /// Light map used for light-gated passability (set by Game).
    weak var light: LightMap?
    var seed: UInt32 = 1
    var noise = Noise(seed: 1)
    private var rng = LCG(state: 1)

    init() {
        tiles = [UInt8](repeating: 0, count: World.W * World.H)
        surface = [Int](repeating: 0, count: World.W)
        biome = [UInt8](repeating: 0, count: World.W)
        explored = [UInt8](repeating: 0, count: World.W * World.H)
    }

    @inline(__always) func get(_ x: Int, _ y: Int) -> Int {
        if x < 0 || x >= w || y < 0 || y >= h { return Tile.bedrock }
        return Int(tiles[y * w + x])
    }
    @inline(__always) func set(_ x: Int, _ y: Int, _ v: Int) {
        if x >= 0 && x < w && y >= 0 && y < h { tiles[y * w + x] = UInt8(v) }
    }
    @inline(__always) func solid(_ x: Int, _ y: Int) -> Bool {
        let t = get(x, y)
        if t == Tile.ghostStone || t == Tile.tideWall { return !gateOpen(x, y, t) }
        return TILES[t].solid
    }
    /// Is a light-gated tile currently revealed/opened by the light falling on it?
    func gateOpen(_ x: Int, _ y: Int, _ t: Int) -> Bool {
        guard let L = light, x >= 0, x < w, y >= 0, y < h else { return false }
        let i = y * w + x
        switch t {
        case Tile.ghostStone: return L.r[i] >= 8 && L.b[i] >= 8
        case Tile.tideWall: return L.b[i] >= 9
        case Tile.hiddenVein: return L.r[i] >= 9
        default: return false
        }
    }
    func surfaceAt(_ x: Int) -> Int { surface[max(0, min(w - 1, x))] }
    func biomeAt(_ x: Int) -> Int { Int(biome[max(0, min(w - 1, x))]) }

    // MARK: generation

    func generate(seed s: UInt32) {
        seed = s; noise = Noise(seed: s); rng = LCG(state: s)
        for i in 0..<tiles.count { tiles[i] = 0; explored[i] = 0 }
        chests = [:]
        let n = noise
        for x in 0..<w {
            let b = n.noise1(Double(x) / 140 + 50) * 0.8 + n.noise1(Double(x) / 45 + 9) * 0.2
            biome[x] = abs(x - w / 2) < 70 ? 0 : (b < 0.38 ? 1 : (b > 0.64 ? 2 : 0))
            let flat = biome[x] == 2 ? 0.5 : 1.0
            let hh = Int(floor(Double(h) * 0.34 + (n.noise1(Double(x) / 52) - 0.5) * 44 * flat + (n.noise1(Double(x) / 12) - 0.5) * 8 * flat))
            surface[x] = hh
            let soil = 4 + n.noise1(Double(x) / 7 + 3) * 4
            for y in hh..<h {
                var t: Int
                let d = Double(y - hh)
                if biome[x] == 2 { t = d < soil + 3 ? Tile.sand : Tile.stone }
                else if biome[x] == 1 { t = y == hh ? Tile.snow : (d < soil ? Tile.dirt : Tile.stone) }
                else { t = y == hh ? Tile.grass : (d < soil ? Tile.dirt : Tile.stone) }
                if y >= h - 3 { t = Tile.bedrock }
                tiles[y * w + x] = UInt8(t)
            }
        }
        // caves
        for x in 0..<w {
            for y in (surface[x] + 3)..<(h - 3) {
                let v = n.noise2(Double(x) / 15, Double(y) / 10) * 0.6 + n.noise2(Double(x) / 6, Double(y) / 5) * 0.4
                let depth = Double(y - surface[x]) / Double(h - surface[x])
                if v > 0.645 - depth * 0.09 { tiles[y * w + x] = 0 }
            }
        }
        func placeOre(_ ore: Int, _ count: Int, _ minD: Int, _ maxD: Int, _ size: Int) {
            for _ in 0..<count {
                let x = rng.int(w)
                let y = surface[x] + minD + rng.int(maxD - minD)
                for _ in 0..<size {
                    let ox = x + rng.int(3) - 1, oy = y + rng.int(3) - 1
                    if ox > 0 && ox < w && oy > 0 && oy < h - 3 && get(ox, oy) == Tile.stone { set(ox, oy, ore) }
                }
            }
        }
        placeOre(Tile.coal, 380, 4, 150, 6); placeOre(Tile.iron, 260, 20, 180, 5)
        placeOre(Tile.gold, 120, 70, 200, 4); placeOre(Tile.diamondOre, 55, 140, 210, 3)
        // lava, glow mushrooms, chests
        for x in 1..<(w - 1) {
            var y = surface[x] + 8
            while y < h - 4 {
                defer { y += 1 }
                if get(x, y) != Tile.air { continue }
                let below = get(x, y + 1)
                let depth = Double(y - surface[x]) / Double(h - surface[x])
                if depth > 0.68 && TILES[below].solid && n.noise2(Double(x) / 9 + 300, Double(y) / 9) > 0.58 {
                    set(x, y, Tile.lava)
                    if get(x, y - 1) == Tile.air && n.noise2(Double(x) / 9 + 300, Double(y - 1) / 9) > 0.6 { set(x, y - 1, Tile.lava) }
                } else if depth > 0.25 && TILES[below].solid && rng.next() < 0.025 {
                    set(x, y, Tile.shroom)
                } else if depth > 0.15 && TILES[below].solid && get(x, y - 1) == Tile.air && rng.next() < 0.004 {
                    set(x, y, Tile.chest); chests["\(x),\(y)"] = loot(depth: depth)
                }
            }
        }
        // vegetation
        var x = 4
        while x < w - 4 {
            defer { x += 1 }
            let top = get(x, surface[x]); let r = rng.next()
            if top == Tile.grass && r < 0.15 {
                let th = 4 + rng.int(4), ty = surface[x] - th
                if ty < 3 { continue }
                for y in stride(from: surface[x] - 1, through: ty, by: -1) { set(x, y, Tile.wood) }
                // rounded canopy, slightly wider than tall
                let rw = 2.6 + rng.next() * 0.8, rh = 2.2 + rng.next() * 0.6
                for dy in -3...2 { for dx in -3...3 {
                    let ex = Double(dx) / rw, ey = Double(dy + 1) / rh
                    if ex * ex + ey * ey > 1 { continue }
                    let yy = ty + dy, xx = x + dx
                    if yy >= 0 && get(xx, yy) == Tile.air { set(xx, yy, Tile.leaves) }
                } }
                x += 3
            } else if top == Tile.grass && r < 0.3 {
                if get(x, surface[x] - 1) == Tile.air { set(x, surface[x] - 1, Tile.flower) }
            } else if top == Tile.snow && r < 0.14 {
                let th = 6 + rng.int(5), ty = surface[x] - th
                if ty < 4 { continue }
                for y in stride(from: surface[x] - 1, through: ty, by: -1) { set(x, y, Tile.pine) }
                var dy = 1
                while dy < th - 1 {
                    let wdt = max(1, (dy + 1) / 2)
                    for dx in -wdt...wdt where dx != 0 {
                        let yy = ty + dy, xx = x + dx
                        if yy >= 0 && get(xx, yy) == Tile.air { set(xx, yy, Tile.snowleaf) }
                    }
                    dy += 2
                }
                if ty - 1 >= 0 && get(x, ty - 1) == Tile.air { set(x, ty - 1, Tile.snowleaf) }
                x += 2
            } else if top == Tile.sand && biome[x] == 2 && r < 0.08 {
                let ch = 1 + rng.int(3)
                for y in stride(from: surface[x] - 1, through: surface[x] - ch, by: -1) { set(x, y, Tile.cactus) }
                x += 1
            }
        }
        // pools
        for x in 1..<(w - 1) {
            if surface[x] >= surface[x - 1] && surface[x] > surface[x + 1] && rng.next() < 0.6 {
                let lvl = min(surface[x - 1], surface[x + 1])
                var l = x, r = x
                while l > 0 && surface[l - 1] >= lvl && surface[l - 1] <= surface[x] + 3 && x - l < 10 { l -= 1 }
                while r < w - 1 && surface[r + 1] >= lvl && surface[r + 1] <= surface[x] + 3 && r - x < 10 { r += 1 }
                for xx in l...r {
                    if lvl < surface[xx] {
                        for y in lvl..<surface[xx] {
                            let t = get(xx, y)
                            if t == Tile.air || t == Tile.flower {
                                set(xx, y, (biome[xx] == 1 && y == lvl) ? Tile.ice : Tile.water)
                            }
                        }
                    }
                }
            }
        }
        generateStory()
    }

    // MARK: story geometry — layers, camp crevice, descent shaft, gated tiles

    private func generateStory() {
        let cx = w / 2; campX = cx; shaftX = cx + 34
        let n = noise
        // --- upper layers: ruined passages (brick rooms with doors and broken platforms)
        for _ in 0..<26 {
            let rw = 6 + rng.int(8), rh = 4 + rng.int(3)
            let rx = 8 + rng.int(w - 16 - rw)
            let ry = surface[rx] + 10 + rng.int(max(1, Layers.bandTop - 14 - (surface[rx] + 10)))
            if ry + rh >= Layers.bandTop - 1 { continue }
            for y in ry...(ry + rh) { for x in rx...(rx + rw) {
                let edge = y == ry || y == ry + rh || x == rx || x == rx + rw
                if edge { if rng.next() < 0.85 { set(x, y, Tile.brick) } else { set(x, y, Tile.rubble) } }
                else { set(x, y, Tile.air) }
            } }
            set(rx, ry + rh - 1, Tile.door); set(rx + rw, ry + rh - 1, Tile.door)
            if rng.next() < 0.5 { for x in (rx + 2)...(rx + rw - 2) where rng.next() < 0.6 { set(x, ry + rh - 2, Tile.platform) } }
            if rng.next() < 0.4 { set(rx + 1 + rng.int(rw - 2), ry + rh - 1, Tile.lantern) }
            if rng.next() < 0.35 { let x = rx + 1 + rng.int(rw - 2); set(x, ry + rh - 1, Tile.chest); chests["\(x),\(ry + rh - 1)"] = loot(depth: 0.3) }
            if rng.next() < 0.5 { set(rx + 1 + rng.int(rw - 2), ry + rh - 1, Tile.greenSpore) }
        }
        // --- collapsed stratum: a hard band of rubble across the whole world (opened in act 3)
        for x in 0..<w {
            for y in (Layers.bandTop - 1)..<(Layers.bandTop + 4) {
                let soft = (y == Layers.bandTop - 1 || y == Layers.bandTop + 3) && n.noise2(Double(x) / 5, Double(y)) < 0.5
                if !soft { set(x, y, Tile.rubble) }
            }
        }
        // --- camp crevice: an elliptical chamber under a crystal crack that lets the sky in
        let cy = (Layers.campTop + Layers.campBottom) / 2
        let rx = 22.0, ry = Double(Layers.campBottom - Layers.campTop) / 2
        for y in (Layers.campTop - 2)...(Layers.campBottom + 3) { for x in (cx - 26)...(cx + 26) {
            let ex = Double(x - cx) / rx, ey = Double(y - cy) / ry
            let d = ex * ex + ey * ey
            if d <= 1 { set(x, y, y >= Layers.campBottom ? (y == Layers.campBottom ? Tile.grass : Tile.dirt) : Tile.air) }
            else if d <= 1.35 { if get(x, y) != Tile.rubble || y > Layers.bandTop + 3 { set(x, y, Tile.stone) } }
        } }
        for x in (cx - 1)...cx { for y in surface[x]..<(Layers.campTop + 1) { set(x, y, Tile.crystal) } }
        for x in (cx - 3)...(cx + 2) { set(x, surface[x] - 1, Tile.air) }   // keep the crack mouth clear
        computeStoryRefs()
        for p in pedestals { set(p.x, p.y, Tile.pedestal); set(p.x, p.y + 1, Tile.brick) }
        set(cx - 5, Layers.campBottom - 1, Tile.greenSpore); set(cx + 6, Layers.campBottom - 1, Tile.flower)
        set(cx - 16, Layers.campBottom - 1, Tile.bench)
        // --- descent shaft (recorded, not dug yet): 3 wide, platforms every 6 rows, then a tunnel into the chamber
        computeStoryRefs()
        // --- red layer: lava shelves, hidden veins beside caves, red spores
        for x in 2..<(w - 2) { for y in Layers.redTop..<Layers.blueTop {
            let t = get(x, y)
            if t == Tile.air {
                if solid(x, y + 1) && get(x, y - 1) == Tile.air {
                    if n.noise2(Double(x) / 7 + 900, Double(y) / 5) > 0.66 { set(x, y, Tile.lava) }
                    else if rng.next() < 0.03 { set(x, y, Tile.redSpore) }
                }
            } else if t == Tile.stone && rng.next() < 0.05 {
                if get(x - 1, y) == Tile.air || get(x + 1, y) == Tile.air || get(x, y - 1) == Tile.air { set(x, y, Tile.hiddenVein) }
            }
        } }
        // --- blue layer: flooded caves, tide walls across passages, blue spores on dry ledges
        for x in 2..<(w - 2) { for y in Layers.blueTop..<Layers.darkTop {
            if get(x, y) == Tile.air && y >= Layers.blueTop + 5 { set(x, y, Tile.water) }
            if get(x, y) == Tile.air && y < Layers.blueTop + 5 && solid(x, y + 1) && rng.next() < 0.04 { set(x, y, Tile.blueSpore) }
            if get(x, y) == Tile.lava { set(x, y, Tile.water) }
        } }
        var wx = 14 + rng.int(10)
        while wx < w - 14 {
            var any = false
            for y in Layers.blueTop..<Layers.darkTop where get(wx, y) == Tile.water { set(wx, y, Tile.tideWall); any = true }
            if any && rng.next() < 0.6 { set(wx + 2, Layers.blueTop + 3, Tile.blueSpore) }
            wx += 18 + rng.int(14)
        }
        // --- ghost rooms (violet): sealed pockets with a chest, in blue and dark layers
        for _ in 0..<9 {
            let gx = 6 + rng.int(w - 20), gy = Layers.blueTop + 8 + rng.int(Layers.cityTop - 14 - (Layers.blueTop + 8))
            for y in gy...(gy + 5) { for x in gx...(gx + 7) {
                let edge = y == gy || y == gy + 5 || x == gx || x == gx + 7
                set(x, y, edge ? Tile.ghostStone : Tile.air)
            } }
            set(gx + 3, gy + 4, Tile.chest); chests["\(gx + 3),\(gy + 4)"] = loot(depth: 0.8) + [ItemStack(id: Item.diamond, n: 1)]
            set(gx + 5, gy + 4, Tile.shroom)
        }
        // --- dark layer: more glow mushrooms; torches die here (handled by the light map)
        for x in 2..<(w - 2) { for y in Layers.darkTop..<Layers.cityTop {
            if get(x, y) == Tile.air && solid(x, y + 1) && rng.next() < 0.05 { set(x, y, rng.next() < 0.5 ? Tile.shroom : (rng.next() < 0.5 ? Tile.redSpore : Tile.blueSpore)) }
        } }
        // --- city: the core chamber at the bottom, walled in crystal
        coreX = cx; coreY = Layers.cityTop + 9
        for y in (Layers.cityTop + 1)...(Layers.cityTop + 11) { for x in (cx - 16)...(cx + 16) {
            let ex = Double(x - cx) / 16, ey = Double(y - (Layers.cityTop + 6)) / 6
            let d = ex * ex + ey * ey
            if d <= 1 { set(x, y, y >= coreY + 1 ? Tile.bedrock : Tile.air) }
            else if d <= 1.3 { set(x, y, Tile.crystal) }
        } }
        set(coreX, coreY, Tile.core); set(coreX, coreY + 1, Tile.bedrock)
        for dx in [-6, 6] { set(coreX + dx, coreY, Tile.pedestal) }
        // make sure a way down exists near the camp: a rough vertical fissure from the chamber floor to the red layer
        var fx = cx + 14
        for y in (Layers.campBottom + 1)...(Layers.redTop + 6) {
            fx += rng.int(3) - 1; fx = max(cx + 8, min(cx + 20, fx))
            for x in (fx - 1)...(fx + 1) where get(x, y) != Tile.crystal { set(x, y, Tile.air) }
            if y % 7 == 0 { set(fx - 1, y, Tile.platform); set(fx + 1, y, Tile.platform) }
        }
    }

    /// Deterministic references (shaft path, pedestals, core) — safe to call after loading a save.
    func computeStoryRefs() {
        let cx = w / 2; campX = cx; shaftX = cx + 34
        pedestals = [(cx - 10, Layers.campBottom - 1), (cx, Layers.campBottom - 1), (cx + 10, Layers.campBottom - 1)]
        coreX = cx; coreY = Layers.cityTop + 9
        shaftTiles = []
        let sx = shaftX
        for y in (surface[sx] - 1)...(Layers.bandTop + 6) { for x in (sx - 1)...(sx + 1) { shaftTiles.append((x, y)) } }
        var ty = Layers.bandTop + 5
        while ty <= Layers.bandTop + 7 { for x in (cx + 20)...(sx + 1) { shaftTiles.append((x, ty)) }; ty += 1 }
    }

    func openShaft() {
        for t in shaftTiles { if get(t.x, t.y) != Tile.crystal { set(t.x, t.y, Tile.air) } }
        var y = surface[shaftX] + 4
        while y < Layers.bandTop + 4 { set(shaftX - 1, y, Tile.platform); set(shaftX + 1, y, Tile.platform); y += 6 }
        for y in (surface[shaftX] - 1)...(Layers.bandTop + 7) { for x in (shaftX - 3)...(shaftX + 3) where get(x, y) == Tile.rubble && (x < shaftX - 1 || x > shaftX + 1) { set(x, y, Tile.stone) } }
    }
    /// Fill the shaft above and through the collapsed stratum.
    func collapseShaft() {
        for t in shaftTiles where t.y >= Layers.bandTop - 14 && t.y <= Layers.bandTop + 3 { set(t.x, t.y, Tile.rubble) }
        for x in (shaftX - 4)...(shaftX + 4) { for y in (Layers.bandTop - 1)..<(Layers.bandTop + 4) { set(x, y, Tile.rubble) } }
    }
    /// Act 3: the stratum becomes diggable; handled by TILES tier override in Game.

    private func loot(depth: Double) -> [ItemStack] {
        var l = [ItemStack(id: [Tile.greenPlant, Tile.redPlant, Tile.bluePlant][rng.int(3)], n: 1 + rng.int(2))]
        if rng.next() < 0.7 { l.append(ItemStack(id: Item.arrow, n: 8 + rng.int(10))) }
        if rng.next() < 0.6 { l.append(ItemStack(id: Item.potion, n: 1 + rng.int(2))) }
        if rng.next() < 0.5 { l.append(ItemStack(id: Tile.iron, n: 2 + rng.int(4))) }
        if depth > 0.45 && rng.next() < 0.45 { l.append(ItemStack(id: Tile.gold, n: 1 + rng.int(3))) }
        if depth > 0.6 && rng.next() < 0.3 { l.append(ItemStack(id: Item.diamond, n: 1)) }
        if rng.next() < 0.2 { l.append(ItemStack(id: Item.lightShard, n: 1)) }
        if rng.next() < 0.25 { l.append(ItemStack(id: Tile.lantern, n: 2)) }
        return l
    }

    /// Autotile bitmask: 1 = up exposed, 2 = right, 4 = down, 8 = left.
    @inline(__always) func autotileMask(_ x: Int, _ y: Int, _ t: Int) -> Int {
        @inline(__always) func connects(_ n: Int) -> Bool {
            if n == t { return true }
            if t == Tile.leaves { return n == Tile.wood }
            if t == Tile.snowleaf { return n == Tile.pine }
            if t == Tile.cactus || t == Tile.glass { return false }
            return TILES[n].solid
        }
        var m = 0
        if !connects(get(x, y - 1)) { m |= 1 }
        if !connects(get(x + 1, y)) { m |= 2 }
        if !connects(get(x, y + 1)) { m |= 4 }
        if !connects(get(x - 1, y)) { m |= 8 }
        return m
    }
}
