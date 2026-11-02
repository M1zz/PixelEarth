import Foundation
import SpriteKit

let TILE_PX: CGFloat = 16
let CHUNK = 32

/// World → scene mapping. World y grows downward; SpriteKit y grows upward.
@inline(__always) func scenePos(_ wx: Double, _ wy: Double) -> CGPoint { CGPoint(x: CGFloat(wx) * TILE_PX, y: -CGFloat(wy) * TILE_PX) }

/// Renders the tile world as a grid of baked chunk textures (32×32 tiles each), re-baking only on change.
final class ChunkRenderer {
    let world: World
    let node = SKNode()
    private var chunks: [Int: SKSpriteNode] = [:]
    private var dirty = Set<Int>()
    private var animated = Set<Int>()
    private var animFrame = 0
    private var animTimer = 0.0
    private let assets = Assets.shared
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let cols: Int, rows: Int
    var coreAwake = false

    init(world: World) {
        self.world = world
        cols = (world.w + CHUNK - 1) / CHUNK; rows = (world.h + CHUNK - 1) / CHUNK
    }

    private func key(_ cx: Int, _ cy: Int) -> Int { cy * cols + cx }

    func invalidate(tileX x: Int, tileY y: Int) {
        // a tile change affects autotile masks of neighbours too
        for dx in -1...1 { for dy in -1...1 {
            let tx = x + dx, ty = y + dy
            if tx < 0 || ty < 0 || tx >= world.w || ty >= world.h { continue }
            dirty.insert(key(tx / CHUNK, ty / CHUNK))
        } }
    }
    func invalidateAll() { for (k, n) in chunks { n.removeFromParent(); _ = k }; chunks.removeAll(); dirty.removeAll(); animated.removeAll() }

    /// Keep chunks covering the visible tile rect (with margin) alive; bake dirty ones.
    func update(visibleX0: Int, visibleY0: Int, visibleX1: Int, visibleY1: Int, dt: Double) {
        animTimer += dt
        if animTimer > 0.22 { animTimer = 0; animFrame = (animFrame + 1) % 4; for k in animated { dirty.insert(k) } }
        let cx0 = max(0, (visibleX0 - 4) / CHUNK), cy0 = max(0, (visibleY0 - 4) / CHUNK)
        let cx1 = min(cols - 1, (visibleX1 + 4) / CHUNK), cy1 = min(rows - 1, (visibleY1 + 4) / CHUNK)
        var wanted = Set<Int>()
        if cx1 >= cx0 && cy1 >= cy0 {
            for cy in cy0...cy1 { for cx in cx0...cx1 { wanted.insert(key(cx, cy)) } }
        }
        for (k, n) in chunks where !wanted.contains(k) { n.removeFromParent(); chunks[k] = nil; animated.remove(k) }
        var baked = 0
        for k in wanted {
            if chunks[k] == nil || dirty.contains(k) {
                if baked >= 6 && chunks[k] != nil { continue }  // spread re-bakes over frames
                bake(k); dirty.remove(k); baked += 1
            }
        }
    }

    private func bake(_ k: Int) {
        let cx = k % cols, cy = k / cols
        let x0 = cx * CHUNK, y0 = cy * CHUNK
        let tw = min(CHUNK, world.w - x0), th = min(CHUNK, world.h - y0)
        let pw = tw * 16, ph = th * 16
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        var hasAnim = false
        for ty in 0..<th {
            let wy = y0 + ty
            let destY = CGFloat(ph - (ty + 1) * 16)
            for tx in 0..<tw {
                let wx = x0 + tx
                let t = world.get(wx, wy)
                let def = TILES[t]
                let dest = CGRect(x: CGFloat(tx * 16), y: destY, width: 16, height: 16)
                // background wall below the surface line
                if (!def.solid || t == Tile.glass) && wy > world.surface[wx] {
                    let kind = wy < world.surface[wx] + 5 ? (world.biome[wx] == 2 ? 2 : 0) : 1
                    if let img = assets.wall(kind: kind, variant: (wx * 7 + wy * 13) & 3) { ctx.draw(img, in: dest) }
                }
                if t == Tile.air { continue }
                // light-gated tiles are baked as their disguise; the scene overlays the truth where the light allows
                let drawT = def.disguise ?? t
                let ddef = TILES[drawT]
                var col = 0
                if ddef.autotile {
                    col = world.autotileMask(wx, wy, drawT) * 2 + ((wx * 31 + wy * 17) & 1)
                } else if t == Tile.pedestal {
                    col = world.pedestalState["\(wx),\(wy)"] ?? 0
                } else if t == Tile.throne {
                    col = world.throneCol["\(wx),\(wy)"] ?? 1
                } else if t == Tile.junction {
                    // two tiles tall: columns 0-1 are the lower half, 2-3 the upper half
                    hasAnim = true
                    col = (world.get(wx, wy + 1) == Tile.junction ? 2 : 0) + (animFrame + wx) % 2
                } else if t == Tile.core {
                    col = coreAwake ? 1 : 0
                } else if ddef.frames > 1 {
                    if t == Tile.platform {
                        var m = 0
                        if world.get(wx + 1, wy) != Tile.platform { m |= 2 }
                        if world.get(wx - 1, wy) != Tile.platform { m |= 8 }
                        col = [0: 0, 2: 1, 8: 2, 10: 3][m] ?? 0
                    } else if t == Tile.flower {
                        col = (wx * 13 + wy * 7) & 3
                    } else {
                        hasAnim = true
                        col = (animFrame + wx) % ddef.frames
                    }
                }
                if let img = assets.tile(drawT, col: col) { ctx.draw(img, in: dest) }
            }
        }
        guard let image = ctx.makeImage() else { return }
        let tex = SKTexture(cgImage: image); tex.filteringMode = .nearest
        if let n = chunks[k] { n.texture = tex; n.size = CGSize(width: pw, height: ph) }
        else {
            let n = SKSpriteNode(texture: tex)
            n.anchorPoint = CGPoint(x: 0, y: 1)
            n.position = scenePos(Double(x0), Double(y0))
            n.size = CGSize(width: pw, height: ph)
            node.addChild(n); chunks[k] = n
        }
        if hasAnim { animated.insert(k) } else { animated.remove(k) }
    }
}
