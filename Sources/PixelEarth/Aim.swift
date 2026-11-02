import Foundation

/// Keyboard targeting: K and L act on what the player faces. W and S look up and down; with A or D held, diagonally.
extension Game {
    private var aimDirection: (x: Int, y: Int) {
        let v = input.up ? -1 : (input.down ? 1 : 0)
        let h = input.left ? -1 : (input.right ? 1 : 0)
        if v != 0 { return (h, v) }
        return (player.face >= 0 ? 1 : -1, 0)
    }

    func nearestEnemy(within range: Double) -> Enemy? {
        var best: Enemy? = nil, bd = range
        for e in enemies {
            let d = hypot(e.x - player.x, (e.y + e.h / 2) - (player.y + player.h / 2)) - e.w / 2
            if d < bd { bd = d; best = e }
        }
        return best
    }

    private func isInteractive(_ t: Int) -> Bool { t == Tile.chest || t == Tile.core || t == Tile.pedestal || t == Tile.throne }

    /// Decides what K acts on this frame: an enemy in reach, then anything to interact with, then the first block in line.
    func updateAim() {
        guard input.keyboardAim else { aimX = input.mouseX; aimY = input.mouseY; return }
        if let e = nearestEnemy(within: heldStats().tool == .bow ? 16 : 3.2) { aimX = e.x; aimY = e.y + e.h / 2; return }
        let d = aimDirection
        let px = Int(floor(player.x)), head = Int(floor(player.y + 0.3)), legs = Int(floor(player.y + player.h - 0.3))
        if d.y == 0 {
            var near: (x: Int, y: Int)? = nil, bd = Int.max
            for y in (head - 2)...(legs + 1) { for x in (px - 3)...(px + 3) where isInteractive(world.get(x, y)) {
                let dist = abs(x - px) + abs(y - legs)
                if dist < bd { bd = dist; near = (x, y) }
            } }
            if let n = near { aimX = Double(n.x) + 0.5; aimY = Double(n.y) + 0.5; return }
        }
        func usable(_ x: Int, _ y: Int) -> Bool { let t = world.get(x, y); return t != Tile.air && !TILES[t].liquid }
        func solidTile(_ x: Int, _ y: Int) -> Bool { let t = world.get(x, y); return usable(x, y) && (TILES[t].solid || t == Tile.platform) }
        var soft: (x: Int, y: Int)? = nil
        for step in 1...5 {
            if d.y == 0 {
                let x = px + d.x * step
                for y in [legs, head] {
                    if solidTile(x, y) { aimX = Double(x) + 0.5; aimY = Double(y) + 0.5; return }
                    if soft == nil && step <= 2 && usable(x, y) { soft = (x, y) }
                }
            } else {
                let x = px + d.x * step, y = (d.y < 0 ? head : legs) + d.y * step
                if usable(x, y) { aimX = Double(x) + 0.5; aimY = Double(y) + 0.5; return }
            }
        }
        if let s = soft { aimX = Double(s.x) + 0.5; aimY = Double(s.y) + 0.5; return }
        aimX = Double(px + d.x) + 0.5
        aimY = Double(d.y == 0 ? legs : (d.y < 0 ? head : legs) + d.y) + 0.5
    }

    /// Where L puts a block: the nearest free tile in the look direction.
    func placeAim() -> (x: Double, y: Double) {
        let d = aimDirection
        let px = Int(floor(player.x)), head = Int(floor(player.y + 0.3)), legs = Int(floor(player.y + player.h - 0.3))
        for p in world.pedestals where abs(p.x - px) <= 3 && abs(p.y - legs) <= 3 { return (Double(p.x) + 0.5, Double(p.y) + 0.5) }
        func free(_ x: Int, _ y: Int) -> Bool { let t = world.get(x, y); return t == Tile.air || t == Tile.water || t == Tile.leaves || t == Tile.snowleaf || t == Tile.flower }
        if d.y == 0 {
            let x = px + d.x
            let y = free(x, legs) ? legs : head
            return (Double(x) + 0.5, Double(y) + 0.5)
        }
        for step in 1...3 {
            let x = px + d.x * step, y = (d.y < 0 ? head : legs) + d.y * step
            if free(x, y) { return (Double(x) + 0.5, Double(y) + 0.5) }
        }
        return (aimX, aimY)
    }
}
