import Foundation

/// Side passages: at a junction the player turns 90 degrees into a passage that runs across the main view.
/// Each passage is a sealed strip at the edge of the same world, so lighting, saving and rendering need nothing new;
/// the turn itself is a teleport covered by a wipe in the scene.
struct Junction {
    let floor: Int
    /// The side of the lair the passage leaves from, and the world edge its strip sits against (-1 left, 1 right).
    let side: Int

    static let all: [Junction] = [Junction(floor: 5, side: -1), Junction(floor: 6, side: 1), Junction(floor: 7, side: -1), Junction(floor: 8, side: 1), Junction(floor: 9, side: -1)]
    static let corridor = 12, passageLength = 46

    /// The opening in the main world, at the end of a short corridor off the floor's lair.
    func mainSpot(worldWidth w: Int) -> (x: Int, y: Int) {
        let t = Reign.thronePosition(floor, worldWidth: w)
        return (t.x + side * (15 + Junction.corridor), t.y)
    }
    /// The opening inside the passage; the passage runs from here toward the world edge.
    func passageSpot(worldWidth w: Int) -> (x: Int, y: Int) {
        let t = Reign.thronePosition(floor, worldWidth: w)
        return (side < 0 ? 6 + Junction.passageLength : w - 7 - Junction.passageLength, t.y)
    }
    /// x range of the passage strip, edge side inclusive.
    func passageXs(worldWidth w: Int) -> ClosedRange<Int> {
        let p = passageSpot(worldWidth: w).x
        return side < 0 ? 6...p : p...(w - 7)
    }
}

enum DecorKind { case namesA, namesB, scratch, sky, herb, bed }
/// A painting placed in a passage; x, y is its top-left tile.
struct Decor { let kind: DecorKind; let x: Int; let y: Int }

extension Junction {
    /// The passage tile `i` steps from its far end back toward the opening.
    func passageX(_ i: Int, worldWidth w: Int) -> Int {
        let xs = passageXs(worldWidth: w)
        return side < 0 ? xs.lowerBound + 2 + i : xs.upperBound - 2 - i
    }
    func decor(worldWidth w: Int) -> [Decor] {
        let y = passageSpot(worldWidth: w).y
        // a painting `width` tiles wide starting `i` steps in, placed by its left edge whichever way the passage runs
        func at(_ i: Int, _ width: Int) -> Int { min(passageX(i, worldWidth: w), passageX(i + width - 1, worldWidth: w)) }
        switch floor {
        case 5: return [Decor(kind: .scratch, x: at(9, 3), y: y - 3), Decor(kind: .herb, x: at(19, 1), y: y - 5)]
        case 6: return [4, 7, 13, 16, 19, 29, 32].enumerated().map { Decor(kind: $0.offset % 2 == 0 ? .namesA : .namesB, x: at($0.element, 3), y: y - 3) }
        case 7: return [20, 24, 28, 32].flatMap { [Decor(kind: .bed, x: at($0, 2), y: y), Decor(kind: .herb, x: at($0, 1), y: y - 5)] }
        case 9: return stride(from: 0, to: 44, by: 4).map { Decor(kind: .sky, x: at($0, 4), y: y - 5) }
        default: return []
        }
    }
}

extension World {
    /// Carves every junction and its passage that is not in the world yet. Safe to call on every load.
    func ensureJunctions() {
        for j in Junction.all {
            let m = j.mainSpot(worldWidth: w), p = j.passageSpot(worldWidth: w)
            if get(m.x, m.y) == Tile.junction && get(p.x, p.y) == Tile.junction { continue }
            // corridor from the lair wall to the opening
            let t = Reign.thronePosition(j.floor, worldWidth: w)
            for i in 13...(15 + Junction.corridor) {
                let x = t.x + j.side * i
                for y in (m.y - 3)...m.y where get(x, y) != Tile.pedestal { set(x, y, Tile.air) }
                set(x, m.y + 1, Tile.brick); set(x, m.y - 4, Tile.brick)
            }
            set(m.x, m.y, Tile.junction); set(m.x, m.y - 1, Tile.junction)
            set(m.x, m.y - 2, Tile.brick); set(m.x, m.y - 3, Tile.brick)
            // the passage: a sealed strip, bedrock all round
            let xs = j.passageXs(worldWidth: w)
            for x in (xs.lowerBound - 1)...(xs.upperBound + 1) {
                for y in (p.y - 6)...(p.y + 2) {
                    let edge = x < xs.lowerBound || x > xs.upperBound || y == p.y - 6 || y == p.y + 2
                    set(x, y, edge ? Tile.bedrock : (y == p.y + 1 ? Tile.brick : Tile.air))
                }
            }
            set(p.x, p.y, Tile.junction); set(p.x, p.y - 1, Tile.junction)
            furnishPassage(j, xs: xs, y: p.y)
        }
    }

    /// Each passage holds what the floor's founder left behind.
    private func furnishPassage(_ j: Junction, xs: ClosedRange<Int>, y: Int) {
        let far = j.side < 0 ? xs.lowerBound + 2 : xs.upperBound - 2
        let step = -j.side          // from the far end back toward the opening
        func at(_ i: Int) -> Int { far + step * i }
        switch j.floor {
        case 5:     // behind the locked door: the brother's side
            for i in [8, 20, 32] { set(at(i), y, Tile.greenPlant) }
            for i in stride(from: 4, to: 40, by: 6) { set(at(i), y - 5, Tile.vine); set(at(i), y - 4, Tile.vine) }
            set(at(14), y - 2, Tile.lantern)
            chests["\(far),\(y)"] = [ItemStack(id: Item.potion, n: 3), ItemStack(id: Tile.greenSpore, n: 4), ItemStack(id: Item.lightShard, n: 1)]
        case 6:     // the east wall of names, and the veins it hid
            for i in stride(from: 3, to: 42, by: 3) { set(at(i), y - 5, i % 2 == 0 ? Tile.gold : Tile.iron) }
            for i in [10, 26] { set(at(i), y - 2, Tile.lantern) }
            chests["\(far),\(y)"] = [ItemStack(id: Item.goldBar, n: 6), ItemStack(id: Tile.redSpore, n: 4), ItemStack(id: Item.lightShard, n: 1)]
        case 7:     // the house past the veil
            for i in 6...16 { set(at(i), y, Tile.water) }
            for i in [18, 36] { set(at(i), y, Tile.bluePlant) }
            set(at(22), y - 2, Tile.lantern)
            chests["\(far),\(y)"] = [ItemStack(id: Item.potion, n: 5), ItemStack(id: Tile.blueSpore, n: 4), ItemStack(id: Item.lightShard, n: 1)]
        case 8:     // the singing dark: no lamps at all, only mushrooms
            for i in stride(from: 5, to: 40, by: 7) { set(at(i), y, Tile.shroom) }
            chests["\(far),\(y)"] = [ItemStack(id: Item.diamond, n: 4), ItemStack(id: Tile.torch, n: 20), ItemStack(id: Item.lightShard, n: 1)]
        default:    // the painted sky
            for i in 0...44 { set(at(i), y - 5, Tile.glass) }
            // lamps die this deep, so mushrooms light the painting
            for i in stride(from: 3, to: 44, by: 6) { set(at(i), y, Tile.shroom) }
            chests["\(far),\(y)"] = [ItemStack(id: Item.diamond, n: 6), ItemStack(id: Item.goldBar, n: 6), ItemStack(id: Item.lightShard, n: 2)]
        }
        set(far, y, Tile.chest)
    }
}

extension Game {
    /// The junction the player is standing at, if any: in the main world or inside a passage.
    func nearbyJunction() -> (junction: Junction, inside: Bool)? {
        let px = Int(floor(player.x)), py = Int(floor(player.y + player.h - 0.1))
        for j in Junction.all {
            let m = j.mainSpot(worldWidth: world.w), p = j.passageSpot(worldWidth: world.w)
            if abs(m.x - px) <= 2 && abs(m.y - py) <= 1 { return (j, false) }
            if abs(p.x - px) <= 2 && abs(p.y - py) <= 1 { return (j, true) }
        }
        return nil
    }

    /// Turns the corner: from the lair corridor into the passage, or back out.
    func turn(at j: Junction, inside: Bool) {
        if defense != nil { tip(L("turn.notNow")); return }
        let dest = inside ? j.mainSpot(worldWidth: world.w) : j.passageSpot(worldWidth: world.w)
        // Step off the opening: back toward the lair when leaving, along the passage when entering.
        let away = inside ? -j.side : j.side
        player.x = Double(dest.x + away * 2) + 0.5; player.y = Double(dest.y) + 1 - player.h - 0.01
        player.vx = 0; player.vy = 0; player.face = Double(away)
        sfx(.open); onStoryEvent?(away > 0 ? "turnRight" : "turnLeft")
        if !inside {
            message(L("passage.\(j.floor).title"))
            if !passagesSeen.contains(j.floor) { passagesSeen.insert(j.floor); message(L("passage.\(j.floor).memory")) }
        }
    }
}
