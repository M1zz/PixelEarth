import Foundation

/// The jar as a lens: one mode at a time shows something through the rock around the player.
/// Every mode works from the start; the matching colour of light reaches further and, for ores, shows the hidden veins.
enum Lens: Int, CaseIterable {
    case path, ore, hidden

    var titleKey: String { ["lens.path", "lens.ore", "lens.hidden"][rawValue] }
    var symbol: String { ["arrow.triangle.branch", "diamond", "eye"][rawValue] }
    /// The jar colour that strengthens this lens.
    func boosted(by jar: Jar) -> Bool { [jar.isGreen, jar.isRed, jar.isBlue][rawValue] }
}

struct LensMark { let x: Int; let y: Int; let kind: Int }   // kind: a tile id, or -1 for the way-down arrow target

extension Game {
    var lensRadius: Int { (18 + jar.brightness) * (lens.boosted(by: jar) ? 3 : 2) / 2 }

    /// Tab: off, path, ore, hidden, off. A lens burns light, so it starts off and can be put away.
    func cycleLens() {
        if !lensActive { lensActive = true; lens = .path }
        else if lens == .hidden { lensActive = false }
        else { lens = Lens(rawValue: lens.rawValue + 1) ?? .path }
        if lensActive && jarEmpty { lensActive = false; tip(L("energy.lensOff")); return }
        sfx(.pick)
        if lensActive { tip(String(format: L("lens.switched"), L(lens.titleKey), L(lens.titleKey + ".what"))) } else { tip(L("lens.off")) }
    }
    /// Clicking a lens button: turn that lens on, or off if it is already on.
    func selectLens(_ m: Lens) {
        sfx(.pick)
        if lensActive && lens == m { lensActive = false; tip(L("lens.off")); return }
        if jarEmpty { tip(L("energy.lensOff")); return }
        lens = m; lensActive = true
        tip(String(format: L("lens.switched"), L(lens.titleKey), L(lens.titleKey + ".what")))
    }

    /// What the current lens shows near the player, plus the nearest way down when the path lens finds none in range.
    func lensMarks() -> (marks: [LensMark], wayDown: (x: Int, y: Int)?) {
        guard lensActive else { return ([], nil) }
        let r = lensRadius, px = Int(floor(player.x)), py = Int(floor(player.y + 1))
        var out: [LensMark] = []
        let ores: Set<Int> = [Tile.coal, Tile.iron, Tile.gold, Tile.diamondOre]
        let hidden: Set<Int> = [Tile.chest, Tile.ghostStone, Tile.tideWall, Tile.throne, Tile.pedestal]
        let paths: Set<Int> = [Tile.crack, Tile.junction, Tile.lightSpring]
        for y in max(0, py - r)...min(world.h - 1, py + r) {
            for x in max(0, px - r)...min(world.w - 1, px + r) {
                let dx = x - px, dy = y - py
                if dx * dx + dy * dy > r * r { continue }
                let t = world.get(x, y)
                switch lens {
                case .ore: if ores.contains(t) || (t == Tile.hiddenVein && jar.isRed) { out.append(LensMark(x: x, y: y, kind: t)) }
                case .hidden: if hidden.contains(t) { out.append(LensMark(x: x, y: y, kind: t)) }
                case .path: if paths.contains(t) { out.append(LensMark(x: x, y: y, kind: t)) }
                }
                if out.count > 400 { break }
            }
        }
        guard lens == .path, !out.contains(where: { $0.kind == Tile.crack }) else { return (out, nil) }
        // the stratum under this floor: point to its nearest cracked vein
        let f = currentFloor
        guard let b = Stage.boundaries[f + 1] else { return (out, nil) }
        var best: Int? = nil
        for x in 0..<world.w where world.get(x, b) == Tile.crack { if best == nil || abs(x - px) < abs(best! - px) { best = x } }
        return (out, best.map { ($0, b) })
    }
}
