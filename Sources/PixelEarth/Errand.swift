import Foundation

/// Grandmother's errand, the first afternoon: carry the jar's light to three neighbours' empty lamps.
/// Each house teaches one thing on the way (walking and jumping, digging with bare hands, hiding the jar),
/// giving light costs the jar's energy, and the last house is empty: its child has gone down the crack.
struct House { let center: Int; let side: Int; let blocked: Bool }

extension World {
    static let houses = [House(center: -16, side: 1, blocked: false), House(center: -40, side: 1, blocked: true), House(center: 60, side: -1, blocked: false)]
    /// Grandmother's box: buried two tiles under soft ground near the first house.
    static let boxOffset = -8

    func houseLamp(_ i: Int) -> (x: Int, y: Int) {
        let x = w / 2 + World.houses[i].center
        return (x, surface[x] - 1)
    }
    var boxSpot: (x: Int, y: Int) { let x = w / 2 + World.boxOffset; return (x, surface[x] + 2) }
    var hasHouses: Bool { (0..<World.houses.count).allSatisfy { let l = houseLamp($0); return get(l.x, l.y) == Tile.emptyLamp || get(l.x, l.y) == Tile.lantern } }

    /// New worlds: the three houses on flattened ground, and the buried box.
    func buildHouses() {
        for h in World.houses {
            let c = w / 2 + h.center, g = surface[c]
            let x0 = c - 3, x1 = c + 3
            for x in (x0 - 1)...(x1 + 1) {
                for y in (g - 7)...(g - 1) { set(x, y, Tile.air) }
                for y in g...max(g, surface[x]) { set(x, y, y == g ? Tile.grass : Tile.dirt) }
                surface[x] = g
            }
            for y in (g - 5)...(g - 1) { set(x0, y, Tile.plank); set(x1, y, Tile.plank) }
            for x in (x0 - 1)...(x1 + 1) { set(x, g - 5, Tile.brick) }
            let door = h.side > 0 ? x1 : x0
            for y in (g - 2)...(g - 1) { set(door, y, h.blocked ? Tile.dirt : Tile.air) }
            set(c, g - 1, Tile.emptyLamp)
        }
        let b = boxSpot
        // no pond over the box: water nearby would pour into the hole as it is dug
        for x in (b.x - 6)...(b.x + 6) { for y in (surface[x] - 6)...(surface[x] + 3) where get(x, y) == Tile.water || get(x, y) == Tile.ice {
            set(x, y, y >= surface[x] ? Tile.dirt : Tile.air)
        } }
        set(b.x, b.y - 2, Tile.grass); set(b.x, b.y - 1, Tile.dirt); set(b.x, b.y, Tile.chest)
        chests["\(b.x),\(b.y)"] = [ItemStack(id: Tile.greenSpore, n: 2), ItemStack(id: Tile.torch, n: 4)]
    }
}

extension Game {
    var housesLit: Int { (0..<World.houses.count).filter { let l = world.houseLamp($0); return world.get(l.x, l.y) == Tile.lantern }.count }

    /// K at an empty lamp: give it some of the jar's light.
    func deliverLight(_ x: Int, _ y: Int) {
        guard spendEnergy(Game.houseCost) else { return }
        setTile(x, y, Tile.lantern); sfx(.heal)
        for _ in 0..<20 { particles.append(Particle(x: Double(x) + 0.5, y: Double(y) + 0.5, vx: Double.random(in: -3...3), vy: Double.random(in: -5 ... -1), t: 1, life: 1, color: RGB(r: 255, g: 236, b: 170))) }
        let i = (0..<World.houses.count).first { world.houseLamp($0).x == x } ?? 0
        message(L("house.\(i).lit"))
    }
}
