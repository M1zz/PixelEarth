import Foundation

struct LightSource { var x: Int; var y: Int; var r: Int; var g: Int; var b: Int }

/// Per-channel flood-fill light propagation (values 0...15), computed on a window around the camera.
final class LightMap {
    let w = World.W, h = World.H
    var r: [UInt8], g: [UInt8], b: [UInt8]
    private var queue: [Int32]
    private var srcs: [LightSource] = []

    init() {
        r = [UInt8](repeating: 0, count: World.W * World.H)
        g = r; b = r
        queue = [Int32](repeating: 0, count: World.W * World.H * 2)
        srcs.reserveCapacity(8192)
    }

    func compute(world: World, x0 ix0: Int, y0 iy0: Int, x1 ix1: Int, y1 iy1: Int, sky: RGB, extra: [LightSource]) {
        let x0 = max(0, ix0), y0 = max(0, iy0), x1 = min(w - 1, ix1), y1 = min(h - 1, iy1)
        if x1 < x0 || y1 < y0 { return }
        srcs.removeAll(keepingCapacity: true)
        let tiles = world.tiles
        for y in y0...y1 {
            for x in x0...x1 {
                let i = y * w + x
                r[i] = 0; g[i] = 0; b[i] = 0
                let t = Int(tiles[i])
                if let l = TILES[t].light {
                    // fire does not burn in the dark layer; living light does
                    if (t == Tile.torch || t == Tile.lantern) && y >= Layers.darkTop { continue }
                    srcs.append(LightSource(x: x, y: y, r: l.r, g: l.g, b: l.b))
                }
            }
        }
        // sky light: open column from the top
        for x in x0...x1 {
            var y = 0
            while y <= y1 {
                let t = Int(tiles[y * w + x])
                if t != Tile.crystal && (TILES[t].solid || t == Tile.leaves || t == Tile.snowleaf) { break }
                if y >= y0 { srcs.append(LightSource(x: x, y: y, r: sky.r, g: sky.g, b: sky.b)) }
                y += 1
            }
        }
        for e in extra where e.x >= x0 && e.x <= x1 && e.y >= y0 && e.y <= y1 { srcs.append(e) }

        for c in 0..<3 {
            var qh = 0, qt = 0
            // seed
            for s in srcs {
                let v = c == 0 ? s.r : (c == 1 ? s.g : s.b)
                let k = s.y * w + s.x
                let cur = c == 0 ? r[k] : (c == 1 ? g[k] : b[k])
                if v > Int(cur) {
                    if c == 0 { r[k] = UInt8(v) } else if c == 1 { g[k] = UInt8(v) } else { b[k] = UInt8(v) }
                    queue[qt] = Int32(s.x); queue[qt + 1] = Int32(s.y); qt += 2
                }
            }
            while qh < qt {
                let x = Int(queue[qh]), y = Int(queue[qh + 1]); qh += 2
                let k = y * w + x
                let v = Int(c == 0 ? r[k] : (c == 1 ? g[k] : b[k]))
                if v <= 1 { continue }
                for d in 0..<4 {
                    let nx = x + (d == 0 ? -1 : (d == 1 ? 1 : 0))
                    let ny = y + (d == 2 ? -1 : (d == 3 ? 1 : 0))
                    if nx < x0 || nx > x1 || ny < y0 || ny > y1 { continue }
                    let nk = ny * w + nx
                    let nt = Int(tiles[nk])
                    let cost = nt == Tile.crystal ? 1 : (TILES[nt].solid ? 3 : (nt == Tile.water ? 2 : 1))
                    let nv = v - cost
                    let cur = Int(c == 0 ? r[nk] : (c == 1 ? g[nk] : b[nk]))
                    if nv > cur {
                        if c == 0 { r[nk] = UInt8(nv) } else if c == 1 { g[nk] = UInt8(nv) } else { b[nk] = UInt8(nv) }
                        if qt + 2 <= queue.count { queue[qt] = Int32(nx); queue[qt + 1] = Int32(ny); qt += 2 }
                    }
                }
            }
        }
    }
}
