import Foundation

/// Floors 5 to 9 are stages: each is sealed from the next by a stratum no tool can break, crossed only through
/// cracked veins a pickaxe can open, and each opens into a hall under its own sky.
enum Stage {
    static let floors = [5, 6, 7, 8, 9]
    /// The stratum above floor f (6...9) spans these rows; floor 5 sits under the collapsed band instead.
    static let boundaries = [6: Layers.redTop, 7: Layers.blueTop, 8: Layers.darkTop, 9: Layers.cityTop]
    static func strataRows(_ b: Int) -> ClosedRange<Int> { (b - 2)...(b + 1) }
    /// First open row of a floor: just under the band or stratum that roofs it.
    static func ceiling(_ f: Int) -> Int { f == 5 ? Layers.bandTop + 4 : (boundaries[f] ?? Layers.redTop) + 2 }
    /// Rows of open air under the ceiling before the ground of the hall.
    static func hallDepth(_ f: Int) -> Int { [5: 9, 6: 11, 7: 11, 8: 9, 9: 6][f] ?? 8 }
    /// Pickaxe veins through each stratum, by column.
    static func crackXs(boundary b: Int, worldWidth w: Int, campFissure: Int?) -> [Int] {
        let j = (b * 7) % 9 - 4
        return [w * 18 / 100 + j, campFissure ?? (w / 2 + 14 - j), w * 82 / 100 - j]
    }

    struct Sky { let top: (Float, Float, Float); let bottom: (Float, Float, Float); let aurora: (Float, Float, Float, Float); let light: RGB; let stars: Float }
    /// Each floor's own sky, and the light that falls from it into the hall.
    static func sky(_ f: Int) -> Sky {
        switch f {
        case 5: return Sky(top: (0.06, 0.16, 0.12), bottom: (0.30, 0.52, 0.30), aurora: (0.80, 1.00, 0.50, 0.55), light: RGB(r: 8, g: 12, b: 8), stars: 0)
        case 6: return Sky(top: (0.14, 0.04, 0.05), bottom: (0.52, 0.20, 0.10), aurora: (1.00, 0.55, 0.25, 0.45), light: RGB(r: 11, g: 6, b: 4), stars: 0)
        case 7: return Sky(top: (0.02, 0.08, 0.20), bottom: (0.10, 0.36, 0.52), aurora: (0.40, 0.85, 1.00, 0.65), light: RGB(r: 5, g: 9, b: 13), stars: 0)
        case 8: return Sky(top: (0.01, 0.01, 0.03), bottom: (0.05, 0.03, 0.09), aurora: (0.50, 0.40, 0.90, 0.15), light: RGB(r: 2, g: 2, b: 4), stars: 0.3)
        default: return Sky(top: (0.18, 0.28, 0.52), bottom: (0.72, 0.78, 0.94), aurora: (1.00, 1.00, 1.00, 0.70), light: RGB(r: 13, g: 13, b: 15), stars: 0)
        }
    }

    /// The title card for arriving on a floor, from its fragment: "6층 · 쉬지 않는 굴 — line".
    static func title(_ f: Int) -> (number: String, name: String, line: String)? {
        guard let frag = Game.fragments[f] else { return nil }
        let parts = frag.components(separatedBy: " — ")
        let head = parts[0].components(separatedBy: " · ")
        return (head.first ?? "", head.count > 1 ? head[1] : "", parts.count > 1 ? parts[1] : "")
    }
}

extension World {
    /// Floor the tile belongs to, if it is in a stage's open hall: open air straight up to that floor's ceiling.
    func openToStageSky(_ x: Int, _ y: Int) -> Bool {
        let f = Layers.index(forY: y)
        guard f >= 5 else { return false }
        let c = Stage.ceiling(f)
        guard y >= c else { return false }
        for yy in c..<y {
            let t = get(x, yy)
            if (TILES[t].solid && t != Tile.glass) || t == Tile.leaves { return false }
        }
        return true
    }

    /// New worlds: halls, hard rock, strata and pickaxe veins. Called at the end of generation.
    func buildStages() {
        let cx = w / 2
        // the camp fissure's column just above the first stratum, so it becomes the middle vein
        let fissure = ((cx + 8)...(cx + 20)).first { get($0, Layers.redTop - 4) == Tile.air }
        carveHalls()
        placeHardRock()
        ensureStrata(full: true, campFissure: fissure)
        ensureLightSprings()
        layoutVersion = 4
    }

    private func carveHalls() {
        let cx = w / 2, n = noise
        for f in Stage.floors {
            let c = Stage.ceiling(f)
            for x in 2..<(w - 2) {
                if f == 5 && abs(x - cx) <= 30 { continue }      // the camp keeps its crevice
                if f == 9 && abs(x - cx) <= 20 { continue }      // and the heart its crystal chamber
                let g = c + Stage.hallDepth(f) + Int(((n.noise1(Double(x) / 23 + Double(f) * 100)) - 0.5) * 6)
                for y in c..<g {
                    let t = get(x, y)
                    if t == Tile.crystal || t == Tile.pedestal || t == Tile.core || t == Tile.bedrock { continue }
                    set(x, y, Tile.air)
                }
                // each hall's ground has its own look (a fixed hash, so the dressing does not depend on generation order)
                let roll = Double((x &* 73856093 ^ f &* 19349663) & 1023) / 1024
                let top = get(x, g)
                guard TILES[top].solid, get(x, g - 1) == Tile.air else { continue }
                switch f {
                case 5: if top == Tile.dirt || top == Tile.stone { set(x, g, Tile.grass) }; if roll < 0.06 { set(x, g - 1, Tile.flower) }
                case 7: if roll < 0.03 { set(x, g - 1, Tile.blueSpore) }
                case 8: if roll < 0.06 { set(x, g - 1, Tile.shroom) }
                default: break
                }
            }
        }
    }

    /// Not all ground gives way: blobs of hard rock inside the floors, kept clear of the veins and strata.
    private func placeHardRock() {
        let n = noise
        let veins = Stage.boundaries.values.flatMap { b in Stage.crackXs(boundary: b, worldWidth: w, campFissure: nil) }
        for y in Stage.ceiling(5)..<(h - 3) {
            if Stage.boundaries.values.contains(where: { abs(y - $0) <= 4 }) { continue }
            for x in 1..<(w - 1) where get(x, y) == Tile.stone {
                if veins.contains(where: { abs(x - $0) <= 5 }) { continue }
                if n.noise2(Double(x) / 9 + 500, Double(y) / 6) > 0.6 { set(x, y, Tile.hardRock) }
            }
        }
    }

    /// Older worlds: trees grown as solid wood become walk-through trunks, counted from the ground up.
    func ensureTrunks() {
        for x in 0..<w {
            var y = surface[x] - 1
            while y > 0 && get(x, y) == Tile.wood { set(x, y, Tile.trunk); y -= 1 }
        }
    }

    /// Places where light can be taken: a spring roughly every 26 columns in every underground floor band,
    /// on a cave floor. Deterministic and only on empty air, so it is safe on older saves.
    func ensureLightSprings() {
        let bands: [(Int, Int)] = [(Layers.bandTop - 40, Layers.bandTop - 2), (Stage.ceiling(5), Layers.redTop - 3), (Stage.ceiling(6), Layers.blueTop - 3),
                                   (Stage.ceiling(7), Layers.darkTop - 3), (Stage.ceiling(8), Layers.cityTop - 3), (Stage.ceiling(9), h - 5)]
        for (i, band) in bands.enumerated() {
            for x in stride(from: 12 + i * 5, to: w - 12, by: 26) {
                let start = band.0 + ((x &* 2654435761) >> 7 & 0x7fffffff) % max(1, band.1 - band.0)
                var y = start, found = false
                for _ in 0..<(band.1 - band.0) {
                    if y > band.1 { y = band.0 }
                    if y > surfaceAt(x) + 8, get(x, y) == Tile.air, get(x, y - 1) == Tile.air, TILES[get(x, y + 1)].solid { found = true; break }
                    y += 1
                }
                if found { set(x, y, Tile.lightSpring) }
            }
        }
    }

    /// Lays the strata and their cracked veins. `full` for new worlds (air and liquid sealed too);
    /// for older saves only solid ground turns, so tunnels already dug stay open.
    func ensureStrata(full: Bool, campFissure: Int? = nil) {
        let keep: Set<Int> = [Tile.throne, Tile.junction, Tile.pedestal, Tile.core, Tile.crystal, Tile.bedrock, Tile.chest]
        for (f, b) in Stage.boundaries {
            let xs = Stage.crackXs(boundary: b, worldWidth: w, campFissure: f == 6 ? campFissure : nil)
            for y in Stage.strataRows(b) {
                for x in 0..<w {
                    let t = get(x, y)
                    if keep.contains(t) { continue }
                    if !full && !TILES[t].solid { continue }
                    let vein = xs.contains { x == $0 || x == $0 + 1 }
                    set(x, y, vein ? Tile.crack : Tile.stratum)
                }
            }
            guard full else { continue }
            // the vein shows from the ground of the hall above, so it can be found
            for x0 in xs { for x in x0...(x0 + 1) {
                var y = Stage.strataRows(b).lowerBound - 1
                while y > Stage.ceiling(f - 1) && TILES[get(x, y)].solid && !keep.contains(get(x, y)) { set(x, y, Tile.crack); y -= 1 }
            } }
        }
    }
}

extension Game {
    static let pickaxe = Item.woodPick
    var hasPickaxe: Bool { countItem(Game.pickaxe) > 0 }

    /// Older saves already past the descent get the pickaxe the camp would have given them.
    func grantPickaxeIfMissing() {
        guard act >= 2, !hasPickaxe else { return }
        _ = addItem(Game.pickaxe, 1)
        message(L("pickaxe.found"))
    }

    /// Why a tile does not give way, for the tip line.
    func digRefusal(_ t: Int) -> String {
        if t == Tile.rubble { return L("dig.rubble") }
        if t == Tile.stratum || t == Tile.hardRock { return L("dig.hard") }
        if !hasPickaxe && TILES[t].tier >= 1 && TILES[t].tier < 9 { return L("dig.needPick") }
        if tileTier(t) >= 9 { return L("dig.never") }
        return L("dig.needLight")
    }
}
