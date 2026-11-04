import SpriteKit

/// The top-down art set (Resources/td_*.png): cave walls with a front face, floors, the walking hero, village props.
final class TDArt {
    static let shared = TDArt()
    let wallTops: [CGImage], wallFaces: [CGImage], wallEdge: CGColor
    let caveFloor: [CGImage], stoneFloor: [CGImage], pathFloor: [CGImage], meadow: [CGImage]
    let props: [String: SKTexture]
    let bushImage: CGImage
    /// [direction][frame]: 0 down, 1 left, 2 right, 3 up
    let walk: [[SKTexture]]

    private init() {
        let walls = Assets.cgImage("td_cave_walls"), floors = Assets.cgImage("td_floors")
        func cell(_ img: CGImage, _ c: Int, _ r: Int, _ w: Int = 16, _ h: Int = 16) -> CGImage { img.cropping(to: CGRect(x: c * 16, y: r * 16, width: w, height: h))! }
        // the wall tops come framed; tile their 12px middle instead, so walls join without seams and edges are drawn only where open
        wallTops = (0..<12).map { TDArt.seamless(cell(walls, $0 % 4, $0 / 4)) }
        wallFaces = (0..<4).map { cell(walls, $0, 3) }
        wallEdge = CGColor(red: 0.42, green: 0.38, blue: 0.52, alpha: 1)
        caveFloor = (0..<4).map { cell(floors, $0, 0) }; stoneFloor = (0..<4).map { cell(floors, 4 + $0, 0) }
        pathFloor = (0..<4).map { cell(floors, $0, 1) }; meadow = (0..<4).map { cell(floors, 4 + $0, 1) }
        let p = Assets.tex("td_village_props")
        props = ["tree": Assets.sub(p, 0, 0, 32, 42), "bush": Assets.sub(p, 32, 0, 16, 16), "fence": Assets.sub(p, 56, 0, 16, 16),
                 "well": Assets.sub(p, 0, 50, 32, 30), "garden": Assets.sub(p, 36, 32, 32, 32), "sign": Assets.sub(p, 72, 32, 16, 16), "lantern": Assets.sub(p, 96, 16, 16, 32)]
        bushImage = Assets.cgImage("td_village_props").cropping(to: CGRect(x: 32, y: 0, width: 16, height: 16))!
        let w = Assets.tex("td_player_walk")
        walk = (0..<4).map { r in (0..<4).map { Assets.sub(w, $0 * 16, r * 24, 16, 24) } }
    }

    /// A village house seen from the front and above (3/4 view): a sloped roof over a plank front with a door,
    /// two windows and the porch lamp of the errand. Drawn in code until the house sheet arrives; 9 x 6 tiles plus a roof peak.
    private var houseCache: [String: SKTexture] = [:]
    static let houseSize = (w: 144, h: 112)
    func house(_ i: Int, lit: Bool, boarded: Bool) -> SKTexture {
        let key = "\(i)\(lit)\(boarded)"
        if let t = houseCache[key] { return t }
        let W = TDArt.houseSize.w, H = TDArt.houseSize.h
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
        func box(_ col: CGColor, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { ctx.setFillColor(col); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        // roofs: rust, teal, violet, matching the stone and moss of the set
        let roofs = [(0.62, 0.30, 0.24), (0.22, 0.48, 0.46), (0.42, 0.32, 0.58)]
        let (rr, rg, rb) = roofs[i % roofs.count]
        let roof = c(rr, rg, rb), roofDark = c(rr * 0.68, rg * 0.68, rb * 0.68), roofLite = c(min(1, rr * 1.3), min(1, rg * 1.3), min(1, rb * 1.3))
        let plank = c(0.55, 0.40, 0.28), plankDark = c(0.38, 0.27, 0.20), stone = c(0.42, 0.40, 0.48), outline = c(0.12, 0.10, 0.14)
        // shadow on the grass
        box(c(0, 0, 0, 0.25), 6, 0, W - 8, 3)
        // front wall, 46px tall, on a stone footing
        let wallTop = 46
        box(outline, 4, 2, W - 8, wallTop - 1)
        box(plank, 5, 3, W - 10, wallTop - 3)
        for y in stride(from: 9, to: wallTop, by: 6) { box(plankDark, 5, y, W - 10, 1) }
        for x in [5, W - 9] { box(plankDark, x, 3, 4, wallTop - 3) }          // corner posts
        box(stone, 4, 2, W - 8, 5); box(outline, 4, 6, W - 8, 1)
        for x in stride(from: 8, to: W - 8, by: 12) { box(c(0.32, 0.30, 0.38), x, 3, 1, 3) }
        // windows: warm when the lamp is lit, dark glass when not
        let glass = lit ? c(1.0, 0.82, 0.42) : c(0.16, 0.20, 0.30), glassLite = lit ? c(1, 0.95, 0.75) : c(0.30, 0.38, 0.52)
        for wx in [22, W - 42] {
            box(outline, wx - 1, 17, 22, 18); box(glass, wx, 18, 20, 16)
            box(plankDark, wx + 9, 18, 2, 16); box(plankDark, wx, 25, 20, 2)
            box(glassLite, wx + 2, 29, 4, 3)
            box(plankDark, wx - 2, 15, 24, 2)                                // sill
        }
        // the door, centred on the lamp cell
        let dx = W / 2 - 9
        box(outline, dx - 1, 6, 20, 32); box(c(0.32, 0.20, 0.14), dx, 7, 18, 30)
        box(c(0.42, 0.27, 0.18), dx + 2, 9, 6, 26); box(c(0.42, 0.27, 0.18), dx + 10, 9, 6, 26)
        box(c(0.95, 0.80, 0.40), dx + 13, 21, 2, 2)
        if boarded {                                                       // the stuck door: boards across it
            box(c(0.62, 0.48, 0.32), dx - 3, 26, 24, 4); box(c(0.62, 0.48, 0.32), dx - 3, 14, 24, 4)
            box(outline, dx - 3, 26, 24, 1); box(outline, dx - 3, 14, 24, 1)
        }
        // the porch lamp beside the door
        let lx = dx + 22
        box(outline, lx + 2, 40, 1, 4)
        if lit { box(c(1, 0.85, 0.4, 0.25), lx - 4, 26, 14, 16) }
        box(outline, lx - 1, 29, 8, 12); box(lit ? c(1, 0.86, 0.45) : c(0.45, 0.48, 0.55), lx, 30, 6, 10)
        if lit { box(c(1, 1, 0.85), lx + 2, 33, 2, 4) }
        // the roof: eaves overhang the wall, rows of shingles up to the ridge
        let eave = wallTop - 4, ridge = H - 10
        for y in eave..<ridge {
            let k = Double(y - eave) / Double(ridge - eave), inset = Int(k * 10)
            box(outline, inset, y, W - inset * 2, 1)
            box((y - eave) % 7 == 0 ? roofDark : roof, inset + 1, y, W - inset * 2 - 2, 1)
        }
        for y in stride(from: eave + 3, to: ridge, by: 7) { for x in stride(from: 8 + (y / 7 % 2) * 6, to: W - 8, by: 12) { box(roofDark, x, y, 1, 5) } }
        box(roofDark, 1, eave, W - 2, 3)                                      // shadow under the eave edge
        box(outline, 10, ridge, W - 20, 5); box(roofLite, 11, ridge + 1, W - 22, 3)
        // a chimney on the right
        box(outline, W - 42, ridge - 4, 14, 18); box(stone, W - 41, ridge - 3, 12, 16); box(c(0.30, 0.28, 0.34), W - 42, ridge + 12, 14, 2)
        let tex = SKTexture(cgImage: ctx.makeImage()!); tex.filteringMode = .nearest
        houseCache[key] = tex
        return tex
    }

    /// Small things drawn in code: grandmother's old torch (a stake wrapped in cloth, a teal flame) and a dropped pickaxe.
    private var extraCache: [String: SKTexture] = [:]
    func extra(_ kind: String, floor: Int = 0, lit: Bool = false) -> SKTexture? {
        let key = kind.hasPrefix("truth") ? "truth\(floor)" : (kind.hasPrefix("graffiti") ? "graffiti" : kind + (lit ? "+" : ""))
        if let t = extraCache[key] { return t }
        if let tex = TDArt.campThing(kind, lit: lit) { extraCache[key] = tex; return tex }
        if kind.hasPrefix("truth") || kind.hasPrefix("graffiti") {
            let tex = kind.hasPrefix("truth") ? TDArt.memento(floor) : TDArt.scratches()
            extraCache[key] = tex; return tex
        }
        let isTorch = kind == "oldTorch"
        guard isTorch || kind.hasPrefix("clueTool") else { return nil }
        let W = 16, H = isTorch ? 24 : 16
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func box(_ r: Double, _ g: Double, _ b: Double, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ a: Double = 1) { ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        if isTorch {
            box(0, 0, 0, 5, 0, 6, 2, 0.3)                                   // foot in the ground
            box(0.16, 0.11, 0.14, 6, 1, 4, 14); box(0.42, 0.30, 0.22, 7, 1, 2, 13)    // the stake
            box(0.16, 0.11, 0.14, 5, 12, 6, 4); box(0.62, 0.58, 0.66, 6, 13, 4, 2)    // cloth wrap, faded
            box(0.16, 0.11, 0.14, 5, 16, 6, 7); box(0.45, 0.95, 0.88, 6, 16, 4, 6)    // the flame
            box(0.85, 1, 0.97, 7, 17, 2, 3); box(0.45, 0.95, 0.88, 7, 22, 2, 1)
        } else {
            // a pickaxe lying with its handle toward the soft wall (drawn pointing right, turned by the scene)
            box(0, 0, 0, 2, 3, 12, 2, 0.25)
            box(0.16, 0.11, 0.14, 1, 6, 11, 3); box(0.55, 0.38, 0.24, 2, 7, 9, 1)
            box(0.16, 0.11, 0.14, 10, 3, 4, 10); box(0.62, 0.62, 0.70, 11, 4, 2, 8); box(0.85, 0.85, 0.92, 11, 10, 1, 2)
        }
        let tex = SKTexture(cgImage: ctx.makeImage()!); tex.filteringMode = .nearest
        extraCache[kind] = tex
        return tex
    }

    /// The camp (a fire ring, altars with a gem of their colour, tents) and the colour gates, drawn in code.
    static func campThing(_ kind: String, lit: Bool) -> SKTexture? {
        let colours: [String: (Double, Double, Double)] = ["R": (0.95, 0.40, 0.30), "G": (0.45, 0.85, 0.40), "B": (0.40, 0.65, 1.0), "C": (0.55, 0.40, 0.80)]
        var W = 16, H = 16
        if kind.hasPrefix("altar") { H = 24 } else if kind.hasPrefix("tent") { W = 24; H = 20 } else if !(kind == "campfire" || kind.hasPrefix("gate")) { return nil }
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func box(_ r: Double, _ g: Double, _ b: Double, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ a: Double = 1) { ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        let ol = (0.16, 0.11, 0.14)
        let k = String(kind.last ?? "C"), (cr, cg, cb) = colours[k] ?? (0.8, 0.8, 0.8)
        if kind == "campfire" {
            box(0, 0, 0, 1, 1, 14, 3, 0.3)
            for (x, y) in [(1, 2), (4, 1), (8, 1), (12, 2), (2, 5), (12, 5)] { box(ol.0, ol.1, ol.2, x, y, 4, 3); box(0.55, 0.53, 0.60, x + 1, y + 1, 2, 1) }   // stone ring
            box(0.45, 0.28, 0.16, 4, 4, 8, 2); box(0.35, 0.2, 0.12, 6, 5, 4, 2)                                                     // logs
            box(1, 0.55, 0.2, 5, 6, 6, 5); box(1, 0.8, 0.35, 6, 7, 4, 5); box(1, 0.95, 0.7, 7, 8, 2, 4); box(1, 0.6, 0.25, 7, 12, 2, 2)   // flame
        } else if kind.hasPrefix("altar") {
            box(0, 0, 0, 2, 0, 12, 2, 0.3)
            box(ol.0, ol.1, ol.2, 2, 1, 12, 5); box(0.50, 0.48, 0.56, 3, 2, 10, 3)            // base
            box(ol.0, ol.1, ol.2, 4, 5, 8, 11); box(0.60, 0.58, 0.66, 5, 6, 6, 9); box(0.45, 0.43, 0.52, 9, 6, 2, 9)   // pillar
            box(ol.0, ol.1, ol.2, 3, 15, 10, 3); box(0.68, 0.66, 0.74, 4, 16, 8, 1)          // top
            let a = lit ? 1.0 : 0.45
            box(ol.0, ol.1, ol.2, 5, 18, 6, 5); box(cr * a, cg * a, cb * a, 6, 19, 4, 3); box(min(1, cr + 0.3) * a, min(1, cg + 0.3) * a, min(1, cb + 0.3) * a, 6, 21, 2, 1)   // the gem
            box(cr, cg, cb, 6, 10, 4, 1, lit ? 1 : 0.4)                                       // a band of colour on the pillar
        } else if kind.hasPrefix("tent") {
            box(0, 0, 0, 1, 0, 22, 2, 0.3)
            for y in 1..<18 { let half = (18 - y) * 11 / 18; box(ol.0, ol.1, ol.2, 12 - half - 1, y, half * 2 + 2, 1); box(cr * 0.75, cg * 0.75, cb * 0.75, 12 - half, y, half * 2, 1) }
            for y in stride(from: 3, to: 17, by: 4) { let half = (18 - y) * 11 / 18; box(cr * 0.55, cg * 0.55, cb * 0.55, 12 - half, y, half * 2, 1) }
            box(ol.0, ol.1, ol.2, 9, 1, 6, 8)
            if lit { box(1, 0.8, 0.45, 10, 1, 4, 7); box(1, 0.95, 0.75, 11, 1, 2, 4) } else { box(0.12, 0.1, 0.14, 10, 1, 4, 7) }   // the door flap
            box(0.5, 0.36, 0.24, 11, 17, 2, 3)
        } else {
            // gates: G roots over rock, R red veins in dark rock, B a standing face of water, C a hush of dark
            switch k {
            case "G":
                box(0.30, 0.20, 0.13, 0, 0, 16, 16)
                ctx.setStrokeColor(CGColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)); ctx.setLineWidth(2)
                for (a, b) in [((0, 3), (16, 12)), ((0, 13), (16, 2)), ((5, 0), (9, 16)), ((12, 0), (3, 16))] { ctx.move(to: CGPoint(x: a.0, y: a.1)); ctx.addLine(to: CGPoint(x: b.0, y: b.1)); ctx.strokePath() }
                for (x, y) in [(3, 5), (11, 9), (7, 12), (13, 3)] { box(0.45, 0.85, 0.40, x, y, 2, 2) }
            case "R":
                box(0.18, 0.15, 0.19, 0, 0, 16, 16)
                ctx.setStrokeColor(CGColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 0.9)); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: 2, y: 14)); ctx.addLine(to: CGPoint(x: 7, y: 9)); ctx.addLine(to: CGPoint(x: 5, y: 5)); ctx.addLine(to: CGPoint(x: 10, y: 1)); ctx.strokePath()
                ctx.move(to: CGPoint(x: 7, y: 9)); ctx.addLine(to: CGPoint(x: 13, y: 11)); ctx.strokePath()
            case "B":
                box(0.12, 0.28, 0.50, 0, 0, 16, 16)
                for y in stride(from: 2, to: 16, by: 4) { box(0.35, 0.60, 0.90, (y * 3) % 7, y, 7, 1) }
                ctx.setStrokeColor(CGColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.8)); ctx.setLineWidth(1); ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
            default:
                box(0.06, 0.04, 0.08, 0, 0, 16, 16)
                ctx.setStrokeColor(CGColor(red: 0.55, green: 0.40, blue: 0.80, alpha: 0.6)); ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12)); ctx.strokeEllipse(in: CGRect(x: 5, y: 5, width: 6, height: 6))
            }
        }
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest; return t
    }

    /// Something a lord left behind: a small bundle wrapped in cloth of the floor's colour, with a faint glimmer.
    static func memento(_ f: Int) -> SKTexture {
        let cols: [Int: (Double, Double, Double)] = [5: (0.45, 0.80, 0.40), 6: (0.90, 0.40, 0.30), 7: (0.35, 0.60, 0.95), 8: (0.60, 0.45, 0.85), 9: (0.92, 0.92, 0.96)]
        let (r, g, b) = cols[f] ?? (0.8, 0.8, 0.8)
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func box(_ rr: Double, _ gg: Double, _ bb: Double, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ a: Double = 1) { ctx.setFillColor(CGColor(red: rr, green: gg, blue: bb, alpha: a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        box(0, 0, 0, 3, 1, 10, 2, 0.3)
        box(0.16, 0.11, 0.14, 3, 2, 10, 8); box(r * 0.7, g * 0.7, b * 0.7, 4, 3, 8, 6); box(r, g, b, 4, 6, 8, 3)       // the bundle
        box(0.16, 0.11, 0.14, 6, 9, 4, 3); box(r * 0.85, g * 0.85, b * 0.85, 7, 9, 2, 2)                          // the knot
        box(0.62, 0.5, 0.36, 3, 5, 10, 1)                                                                        // a cord around it
        box(1, 1, 0.92, 5, 7, 1, 1)
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest; return t
    }
    /// Words scratched into a wall: pale strokes.
    static func scratches() -> SKTexture {
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.92, green: 0.88, blue: 0.80, alpha: 0.85))
        for (x, y, w) in [(2, 11, 5), (8, 11, 6), (3, 8, 4), (8, 8, 3), (12, 8, 2), (2, 5, 6), (9, 5, 4)] { ctx.fill(CGRect(x: x, y: y, width: w, height: 1)) }
        for (x, y) in [(4, 10), (10, 10), (5, 7), (11, 4)] { ctx.fill(CGRect(x: x, y: y, width: 1, height: 2)) }
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest; return t
    }

    /// Repeats the inner 12x12 of a framed tile across 16x16.
    static func seamless(_ img: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        let inner = img.cropping(to: CGRect(x: 2, y: 2, width: 12, height: 12))!
        for oy in [-8, 4] { for ox in [-8, 4] { ctx.draw(inner, in: CGRect(x: ox, y: oy, width: 12, height: 12)) } }
        ctx.draw(inner, in: CGRect(x: 2, y: 2, width: 12, height: 12))
        return ctx.makeImage()!
    }
}
