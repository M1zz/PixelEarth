import SpriteKit

/// The jar, drawn pixel by pixel from what is inside it: the light breathing in its colour,
/// soil tinted by the minerals fed, sprouts for each spore, an iron bail once it is a lantern,
/// a carrying frame once it is a greenhouse. The HUD icon and the jar panel use the same picture.
enum JarArt {
    static let w = 20, h = 24
    static let frameCount = 3                      // the light breathes: small, mid, full

    private static var cache: [String: SKTexture] = [:]

    static func texture(_ jar: Jar, frame: Int) -> SKTexture {
        let key = "\(jar.stage) \(jar.light.r) \(jar.light.g) \(jar.light.b) \(jar.iron) \(jar.gold) \(jar.diamond) \(jar.sporeR) \(jar.sporeG) \(jar.sporeB) \(Int(jar.water / 3)) \(Int(jar.moss / 3)) \(frame)"
        if let t = cache[key] { return t }
        let t = render(jar, frame: frame)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = t
        return t
    }

    static func frames(_ jar: Jar) -> [SKTexture] { (0..<frameCount).map { texture(jar, frame: $0) } }

    // MARK: drawing

    private struct C { var r, g, b, a: Double
        static let clear = C(r: 0, g: 0, b: 0, a: 0)
        init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
        init(hex: UInt32) { r = Double(hex >> 16 & 255) / 255; g = Double(hex >> 8 & 255) / 255; b = Double(hex & 255) / 255; a = 1 }
        func mix(_ o: C, _ t: Double) -> C { C(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t) }
    }

    private static let outline = C(hex: 0x10131C)
    private static let glassDark = C(hex: 0x1E2C40)
    private static let glassEdge = C(hex: 0x3E5468)
    private static let shine = C(hex: 0xDDF4FF)
    private static let cork = C(hex: 0x8A5A33), corkTop = C(hex: 0xB9834F)
    private static let iron = C(hex: 0x6B7280), ironLight = C(hex: 0x9CA3AF)
    private static let wood = C(hex: 0x6B4529), woodLight = C(hex: 0x92633D)

    /// Inside of the glass, per row: (first x, last x). Rows not listed are not glass.
    private static let body: [Int: (Int, Int)] = {
        var b: [Int: (Int, Int)] = [5: (7, 12), 6: (7, 12), 7: (5, 14)]
        for y in 8...20 { b[y] = (4, 15) }
        b[8] = (5, 14); b[20] = (5, 14); b[21] = (6, 13)
        return b
    }()

    private static func render(_ jar: Jar, frame: Int) -> SKTexture {
        var px = [C](repeating: .clear, count: w * h)
        func set(_ x: Int, _ y: Int, _ c: C) { if x >= 0 && x < w && y >= 0 && y < h { px[y * w + x] = c } }
        func get(_ x: Int, _ y: Int) -> C { (x >= 0 && x < w && y >= 0 && y < h) ? px[y * w + x] : .clear }

        let l = jar.light
        let bright = Double(jar.brightness) / 15
        // the hue of what was fed, at full strength; a dim jar is still a handful of sky, so it leans to skymist
        let top = Double(max(1, jar.brightness))
        let hue = C(r: Double(l.r) / top, g: Double(l.g) / top, b: Double(l.b) / top)
        let mist = max(0, 1 - bright * 1.4)
        let mistA = C(hex: 0x4FE3C8), mistB = C(hex: 0xA77BFF)
        let lightC = hue.mix(mistA, mist * 0.85).mix(C(r: 0, g: 0, b: 0), 0.15 * (1 - bright))
        let bandC = hue.mix(mistB, mist * 0.85)
        let core = lightC.mix(C(r: 1, g: 1, b: 1), 0.5)
        let glow = 0.55 + bright * 0.45

        // carrying frame (greenhouse stage) sits behind the jar
        if jar.stage >= 2 {
            for y in 6...23 { set(1, y, wood); set(18, y, wood); set(2, y, woodLight); set(17, y, woodLight) }
            for x in 1...18 { set(x, 10, wood); set(x, 19, wood) }
        }

        // soil, water and moss fill the bottom rows of the glass
        let minerals = jar.iron + jar.gold + jar.diamond
        let soilRows = 2 + min(3, minerals / 4)
        let soilTop = 21 - soilRows + 1
        let soilBase = C(hex: 0x4A3324).mix(C(hex: 0x8C3A2A), Double(jar.iron) / 10).mix(C(hex: 0x9A7A2A), Double(jar.gold) / 12).mix(C(hex: 0x2A6A78), Double(jar.diamond) / 12)
        let waterRow = jar.water > 2 ? soilTop - 1 : -1

        for (y, span) in body {
            for x in span.0...span.1 {
                var c: C
                if y >= soilTop {
                    c = (y == soilTop) ? soilBase.mix(C(r: 1, g: 1, b: 1), 0.12) : soilBase.mix(.init(r: 0, g: 0, b: 0), Double(y - soilTop) * 0.08)
                } else if y == waterRow {
                    c = C(hex: 0x2F5F9E).mix(lightC, 0.25)
                } else {
                    // the light: two curtains of mist waving across the glass around a breathing core
                    let ph = Double(frame) * 2.1
                    let waveA = 10.5 + sin(Double(x) * 0.85 + ph) * 1.3
                    let waveB = 14.5 + sin(Double(x) * 0.7 - ph + 1.5) * 1.2
                    let dx = Double(x) - 9.5, dy = (Double(y) - 12.5) * 0.9
                    let d = (dx * dx + dy * dy).squareRoot()
                    let r = (1.6 + Double(frame) * 0.5) * glow
                    c = glassDark.mix(lightC, 0.18 * glow)
                    if abs(Double(y) - waveB) < 0.8 { c = bandC.mix(glassDark, 0.35) }
                    if abs(Double(y) - waveA) < 0.8 { c = lightC.mix(glassDark, 0.2) }
                    if d < r * 1.7 { c = c.mix(lightC, 0.55) }
                    if d < r { c = core }
                }
                set(x, y, c)
            }
        }
        // mineral flecks in the soil, in a fixed scatter so the jar does not flicker
        var spots = [(Int, Int)]()
        for i in 0..<minerals { spots.append((5 + (i * 5) % 10, soilTop + 1 + (i * 3) % max(1, soilRows - 1))) }
        for (i, s) in spots.enumerated() {
            let c = i < jar.iron ? C(hex: 0xE07A4F) : (i < jar.iron + jar.gold ? C(hex: 0xF2C14E) : C(hex: 0x8FF0FF))
            if body[s.1].map({ s.0 >= $0.0 && s.0 <= $0.1 }) ?? false { set(s.0, s.1, c) }
        }
        // moss on the soil line
        for i in 0..<min(6, Int(jar.moss / 2)) { set(5 + (i * 7) % 10, soilTop - 1, C(hex: 0x4FA35A)) }
        // a sprout for each spore: a stem and a glowing bud
        let sprouts: [(Bool, Int, C)] = [(jar.sporeR, 6, C(hex: 0xFF6B7F)), (jar.sporeG, 9, C(hex: 0x7FE89A)), (jar.sporeB, 12, C(hex: 0x7FC8FF))]
        for (has, x, bud) in sprouts where has {
            set(x, soilTop - 1, C(hex: 0x3F7F4A)); set(x, soilTop - 2, C(hex: 0x3F7F4A))
            set(x, soilTop - 3, bud); set(x - 1, soilTop - 2, C(hex: 0x3F7F4A).mix(bud, 0.3))
        }

        // glass edge, then shine
        for (y, span) in body { set(span.0, y, get(span.0, y).mix(glassEdge, 0.55)); set(span.1, y, get(span.1, y).mix(glassEdge, 0.55)) }
        for y in 9...15 { set(5, y, get(5, y).mix(shine, 0.6)) }
        set(5, 17, get(5, 17).mix(shine, 0.4)); set(13, 9, get(13, 9).mix(shine, 0.5))

        // cork
        for x in 6...13 { set(x, 3, corkTop); set(x, 4, cork) }

        // lantern stage: iron cap, a band at the shoulder and a bail handle
        if jar.stage >= 1 {
            for x in 6...13 { set(x, 3, ironLight); set(x, 4, iron) }
            for x in 5...14 where body[7].map({ x >= $0.0 && x <= $0.1 }) ?? false { set(x, 7, get(x, 7).mix(iron, 0.7)) }
            for (x, y) in [(6, 2), (7, 1), (8, 0), (9, 0), (10, 0), (11, 0), (12, 1), (13, 2)] { set(x, y, iron) }
        }

        // 1px dark outline around everything drawn
        let filled = px.map { $0.a > 0 }
        for y in 0..<h { for x in 0..<w where !filled[y * w + x] {
            let n = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].contains { (nx, ny) in nx >= 0 && nx < w && ny >= 0 && ny < h && filled[ny * w + nx] }
            if n { px[y * w + x] = outline }
        } }

        // to a texture: rows go top-down in the buffer, CGImage rows go top-down too
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let c = px[i]
            bytes[i * 4] = UInt8(max(0, min(255, c.r * c.a * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, c.g * c.a * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, c.b * c.a * 255)))
            bytes[i * 4 + 3] = UInt8(max(0, min(255, c.a * 255)))
        }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .nearest
        return t
    }
}
