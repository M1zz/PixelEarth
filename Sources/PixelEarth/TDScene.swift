import SpriteKit
import AppKit

/// Draws the top-down game: the floor's map baked to one texture, light over it, creatures sorted by depth, and the HUD.
final class TDScene: SKScene {
    let game = TDGame()
    let assets = Assets.shared
    let cam = SKCameraNode()
    let mapNode = SKSpriteNode(), lightNode = SKSpriteNode(), entityNode = SKNode(), fxNode = SKNode(), lensNode = SKNode()
    let playerNode = SKSpriteNode(), grandmaNode = SKSpriteNode()
    var enemyNodes: [UUID: SKSpriteNode] = [:], dropNodes: [UUID: SKSpriteNode] = [:]
    let hud = SKNode(), grade = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
    var keys = Set<String>(), lastTime: TimeInterval = 0, mapDirty = true, lightT = 0.0, lensT = 0.0, titleOpen = true
    let zoom: CGFloat = 2.4
    // HUD parts
    let msgLabel = SKLabelNode(fontNamed: HUD.fontBold), tipLabel = SKLabelNode(fontNamed: HUD.fontBold)
    let objTitle = SKLabelNode(fontNamed: HUD.fontBold), objDetail = SKLabelNode(fontNamed: HUD.fontBold), progressLabel = SKLabelNode(fontNamed: HUD.fontBold)
    let hpFill = SKSpriteNode(color: SKColor(red: 1, green: 0.86, blue: 0.55, alpha: 1), size: CGSize(width: 1, height: 10))
    let energyFill = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 6))
    let hpText = SKLabelNode(fontNamed: HUD.fontBold), energyText = SKLabelNode(fontNamed: HUD.fontBold)
    let jarIcon = SKSpriteNode(), hotbar = SKNode(), stage = SKNode(), title = SKNode(), keysLabel = SKLabelNode(fontNamed: HUD.fontBold)
    var lensButtons: [SKNode] = []
    let focusPanel = SKNode(), focusName = SKLabelNode(fontNamed: HUD.fontBold), focusFill = SKSpriteNode(color: SKColor(red: 1, green: 0.42, blue: 0.4, alpha: 1), size: CGSize(width: 1, height: 10))
    let hurtOverlay = SKSpriteNode(color: SKColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1), size: CGSize(width: 10, height: 10))
    var combatButtons: [(node: SKNode, shade: SKSpriteNode)] = []
    // living details: shadows under everyone, puffs and motes that run on their own actions, glows and sparkles of the map
    let shadowNode = SKNode(), animNode = SKNode(), decorNode = SKNode()
    var dustT = 0.0, moteT = 0.0, lastSwing = 0.0
    static let shadowTex: SKTexture = {
        let ctx = CGContext(data: nil, width: 12, height: 5, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.35)); ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 5))
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest; return t
    }()
    static let dotTex: SKTexture = {
        let ctx = CGContext(data: nil, width: 3, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 1, y: 0, width: 1, height: 3)); ctx.fill(CGRect(x: 0, y: 1, width: 3, height: 1))
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest; return t
    }()
    var msgQueue: [String] = [], msgT = 0.0, tipT = 0.0
    weak var classic: GameScene?
    var onClassic: (() -> Void)?

    override func didMove(to view: SKView) {
        backgroundColor = .black
        camera = cam; addChild(cam); cam.setScale(1 / zoom)
        mapNode.anchorPoint = CGPoint(x: 0, y: 1); addChild(mapNode)
        addChild(lensNode); lensNode.zPosition = 30
        addChild(entityNode); addChild(fxNode); fxNode.zPosition = 20
        shadowNode.zPosition = 5; addChild(shadowNode)
        decorNode.zPosition = 6; addChild(decorNode)
        animNode.zPosition = 27; addChild(animNode)
        lightNode.anchorPoint = CGPoint(x: 0, y: 1); lightNode.blendMode = .multiply; lightNode.zPosition = 25; addChild(lightNode)
        playerNode.anchorPoint = CGPoint(x: 0.5, y: 0.12); playerNode.size = CGSize(width: 20, height: 32); entityNode.addChild(playerNode)
        grandmaNode.anchorPoint = CGPoint(x: 0.5, y: 0.12); grandmaNode.size = CGSize(width: 20, height: 32); entityNode.addChild(grandmaNode)
        grade.blendMode = .multiply; grade.zPosition = -1; cam.addChild(grade)
        cam.addChild(hud); hud.zPosition = 100
        buildHUD()
        game.onMessage = { [weak self] in self?.showMessage($0) }
        game.onTip = { [weak self] in self?.showTip($0) }
        game.onTile = { [weak self] in self?.mapDirty = true }
        game.onSFX = { Sound.shared.play($0) }
        game.onFloor = { [weak self] f in self?.arrived(f) }
        game.onStage = { [weak self] n, name, line in self?.showStage(n, name, line) }
        // a world behind the title
        game.newGame(seed: 20261103); game.loaded = false; msgQueue = []; msgLabel.alpha = 0
        showTitle()
    }

    func save() { game.save() }

    // MARK: map baking

    func bake() {
        let m = game.map, T = 16, art = TDArt.shared
        guard let ctx = CGContext(data: nil, width: m.w * T, height: m.h * T, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .none
        let village = game.floor == 0
        // rock is anything solid that is not part of the village; in the village, the wood edge is bushes
        let rock: (Int, Int) -> Bool = { x, y in let t = m.get(x, y); return TILES[t].solid && !village }
        func hsh(_ x: Int, _ y: Int) -> Int { (x &* 73856093 ^ y &* 19349663) & 0x7fffffff }
        let floorSet = village ? art.meadow : (game.floor >= 5 ? art.caveFloor : art.stoneFloor)
        for y in 0..<m.h { for x in 0..<m.w {
            let r = CGRect(x: x * T, y: (m.h - 1 - y) * T, width: T, height: T)
            let t = m.get(x, y)
            ctx.draw((t == Tile.tdPath ? art.pathFloor : floorSet)[hsh(x, y) % 4], in: r)
            if t == Tile.air || t == Tile.tdPath || t == Tile.propBlock { continue }
            if rock(x, y) {
                if !rock(x, y + 1) {
                    ctx.draw(art.wallFaces[hsh(x, y) % 4], in: r)
                } else {
                    ctx.draw(art.wallTops[hsh(x, y) % 12], in: r)
                    ctx.setFillColor(art.wallEdge)
                    if !rock(x, y - 1) { ctx.fill(CGRect(x: r.minX, y: r.maxY - 1, width: 16, height: 1)) }
                    if !rock(x - 1, y) { ctx.fill(CGRect(x: r.minX, y: r.minY, width: 1, height: 16)) }
                    if !rock(x + 1, y) { ctx.fill(CGRect(x: r.maxX - 1, y: r.minY, width: 1, height: 16)) }
                }
                material(ctx, t, r, hsh(x, y))
                continue
            }
            switch t {
            case Tile.dirt where village:                                     // a mound of soft earth on the grass
            ctx.setFillColor(CGColor(red: 0.30, green: 0.20, blue: 0.13, alpha: 1)); ctx.fillEllipse(in: r.insetBy(dx: 1, dy: 2).offsetBy(dx: 0, dy: -1))
            ctx.setFillColor(CGColor(red: 0.50, green: 0.35, blue: 0.22, alpha: 1)); ctx.fillEllipse(in: r.insetBy(dx: 2, dy: 4).offsetBy(dx: 0, dy: 1))
            ctx.setFillColor(CGColor(red: 0.62, green: 0.46, blue: 0.30, alpha: 1)); ctx.fill(CGRect(x: r.minX + 5, y: r.minY + 9, width: 3, height: 1))
        case Tile.trunk: if !m.props.contains(where: { $0.x == x && $0.y == y }) { ctx.draw(art.bushImage, in: r) }
            case Tile.water, Tile.lava:
                let deep = t == Tile.water ? CGColor(red: 0.16, green: 0.38, blue: 0.56, alpha: 1) : CGColor(red: 0.85, green: 0.35, blue: 0.12, alpha: 1)
                let lite = t == Tile.water ? CGColor(red: 0.34, green: 0.62, blue: 0.80, alpha: 1) : CGColor(red: 1, green: 0.7, blue: 0.3, alpha: 1)
                ctx.setFillColor(deep); ctx.fill(r)
                ctx.setFillColor(lite); ctx.fill(CGRect(x: r.minX + CGFloat(hsh(x, y) % 10), y: r.minY + CGFloat(hsh(y, x) % 12), width: 4, height: 1))
                if m.get(x, y - 1) != t { ctx.setFillColor(lite); ctx.fill(CGRect(x: r.minX, y: r.maxY - 2, width: 16, height: 2)) }
            default:
                if let img = assets.tile(t, col: 0) { ctx.draw(img, in: r) }
            }
        } }
        if let img = ctx.makeImage() {
            let tex = SKTexture(cgImage: img); tex.filteringMode = .nearest
            mapNode.texture = tex; mapNode.size = CGSize(width: m.w * T, height: m.h * T); mapNode.position = .zero
        }
        rebuildProps(); rebuildDecor()
        mapDirty = false
    }

    /// What a wall is made of shows on its face: soft earth browner, ore glinting, cracks split, hard rock darker.
    func material(_ ctx: CGContext, _ t: Int, _ r: CGRect, _ h: Int) {
        func dots(_ c: CGColor, _ n: Int) { ctx.setFillColor(c); for k in 0..<n { let v = (h >> (k * 4)) & 0xff; ctx.fill(CGRect(x: r.minX + 3 + CGFloat(v % 10), y: r.minY + 3 + CGFloat((v / 10) % 10), width: 2, height: 2)) } }
        switch t {
        case Tile.dirt: ctx.setFillColor(CGColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 0.55)); ctx.fill(r)
        case Tile.hardRock: ctx.setFillColor(CGColor(gray: 0, alpha: 0.3)); ctx.fill(r)
        case Tile.bedrock: ctx.setFillColor(CGColor(gray: 0, alpha: 0.55)); ctx.fill(r)
        case Tile.crystal: ctx.setFillColor(CGColor(red: 0.7, green: 0.95, blue: 1, alpha: 0.22)); ctx.fill(r)
        case Tile.ghostStone: ctx.setFillColor(CGColor(red: 0.6, green: 0.45, blue: 0.9, alpha: 0.18)); ctx.fill(r)
        case Tile.coal: dots(CGColor(gray: 0.05, alpha: 1), 3)
        case Tile.iron: dots(CGColor(red: 0.9, green: 0.6, blue: 0.45, alpha: 1), 3)
        case Tile.gold: dots(CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), 3)
        case Tile.diamondOre: dots(CGColor(red: 0.55, green: 0.95, blue: 1, alpha: 1), 3)
        case Tile.crack:
            ctx.setStrokeColor(CGColor(red: 0.85, green: 1, blue: 0.85, alpha: 1)); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: r.minX + 8, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.minX + 5, y: r.minY + 10)); ctx.addLine(to: CGPoint(x: r.minX + 10, y: r.minY + 6)); ctx.addLine(to: CGPoint(x: r.minX + 7, y: r.minY)); ctx.strokePath()
        case Tile.plank: ctx.setFillColor(CGColor(red: 0.5, green: 0.33, blue: 0.2, alpha: 0.85)); ctx.fill(r)
        case Tile.brick: ctx.setFillColor(CGColor(red: 0.45, green: 0.42, blue: 0.5, alpha: 0.85)); ctx.fill(r)
        default: break
        }
    }

    /// Trees, wells, fences, lanterns: sprites sorted with the creatures, so the player walks behind them.
    let propNode = SKNode()
    func litProp(_ k: String) -> Bool {
        if k.hasPrefix("altar") { return game.altarLit(String(k.dropFirst(5))) }
        if k.hasPrefix("tent") { return game.altarLit(String(k.dropFirst(4))) }
        return false
    }
    func rebuildProps() {
        if propNode.parent == nil { entityNode.addChild(propNode) }
        propNode.removeAllChildren()
        for p in game.map.props {
            let tex: SKTexture
            if p.kind.hasPrefix("house"), let i = Int(p.kind.dropFirst(5)), i < game.map.houses.count {
                let l = game.map.houses[i], spot = TD.houseSpots[i]
                tex = TDArt.shared.house(i, lit: game.map.get(l.x, l.y) == Tile.lantern, boarded: spot.blocked && game.map.get(spot.x, spot.y + 3) == Tile.dirt)
            } else if let t = TDArt.shared.props[p.kind] ?? TDArt.shared.extra(p.kind, floor: game.floor, lit: litProp(p.kind)) { tex = t } else { continue }
            let n = SKSpriteNode(texture: tex); n.anchorPoint = CGPoint(x: 0.5, y: 0)
            let w = CGFloat(p.size.w), h = CGFloat(p.size.h)
            if p.kind.hasPrefix("house") { n.size = CGSize(width: TDArt.houseSize.w, height: TDArt.houseSize.h) }
            n.position = CGPoint(x: (CGFloat(p.x) + w / 2) * 16, y: -(CGFloat(p.y) + h) * 16 + (p.kind == "tree" ? -2 : 0))
            n.zPosition = 10 + (CGFloat(p.y) + h - 0.5) * 0.01
            propNode.addChild(n)
            if p.kind.hasPrefix("gate") {                                // flat on the wall, with a slow glow of its colour
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5); n.position = pos(Double(p.x) + 0.5, Double(p.y) + 0.5); n.zPosition = 8
                let c: SKColor = ["gateG": SKColor(red: 0.5, green: 1, blue: 0.45, alpha: 1), "gateR": SKColor(red: 1, green: 0.45, blue: 0.3, alpha: 1), "gateB": SKColor(red: 0.45, green: 0.7, blue: 1, alpha: 1)][p.kind] ?? SKColor(red: 0.6, green: 0.45, blue: 0.9, alpha: 1)
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 30, height: 30); g.color = c; g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0.25; g.zPosition = 1; n.addChild(g)
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 1.6 + Double(p.x % 5) / 5), .fadeAlpha(to: 0.2, duration: 1.6)])))
            }
            if p.kind == "campfire" {                                      // flicker and sparks
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 56, height: 56); g.color = SKColor(red: 1, green: 0.7, blue: 0.35, alpha: 1); g.colorBlendFactor = 1; g.blendMode = .add; g.position = CGPoint(x: 0, y: 8); g.alpha = 0.6; g.zPosition = 1; n.addChild(g)
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.85, duration: 0.12), .fadeAlpha(to: 0.5, duration: 0.2), .fadeAlpha(to: 0.7, duration: 0.15)])))
                n.run(.repeatForever(.sequence([.run { [weak n] in
                    guard let n else { return }
                    let sp = SKSpriteNode(color: SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 1), size: CGSize(width: 1.5, height: 1.5)); sp.position = CGPoint(x: CGFloat.random(in: -3...3), y: 10); sp.zPosition = 2; n.addChild(sp)
                    sp.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -6...6), y: 22, duration: 1), .fadeOut(withDuration: 1)]), .removeFromParent()]))
                }, .wait(forDuration: 0.25)])))
            }
            if p.kind.hasPrefix("altar") && litProp(p.kind) {
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 34, height: 34); g.blendMode = .add; g.position = CGPoint(x: 0, y: 20); g.alpha = 0.6; g.zPosition = 1
                g.color = ["altarR": SKColor(red: 1, green: 0.45, blue: 0.3, alpha: 1), "altarG": SKColor(red: 0.5, green: 1, blue: 0.45, alpha: 1)][p.kind] ?? SKColor(red: 0.45, green: 0.7, blue: 1, alpha: 1); g.colorBlendFactor = 1; n.addChild(g)
                g.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 1), .scale(to: 1, duration: 1)])))
            }
            if p.kind.hasPrefix("graffiti") { n.anchorPoint = CGPoint(x: 0.5, y: 0.5); n.position = pos(Double(p.x) + 0.5, Double(p.y) + 0.6); n.zPosition = 8 }
            if p.kind.hasPrefix("truth"), let i = Int(p.kind.dropFirst(5)), !game.map.has("truth:\(i)") {
                // not yet read: a glint that comes and goes
                let sp = SKSpriteNode(texture: TDScene.dotTex); sp.size = CGSize(width: 7, height: 7); sp.blendMode = .add; sp.position = CGPoint(x: 4, y: 13); sp.alpha = 0; sp.zPosition = 1; n.addChild(sp)
                sp.run(.repeatForever(.sequence([.group([.fadeAlpha(to: 1, duration: 0.3), .scale(to: 1.3, duration: 0.3)]), .group([.fadeOut(withDuration: 0.5), .scale(to: 0.7, duration: 0.5)]), .wait(forDuration: 1.4)])))
            }
            if p.kind.hasPrefix("clueTool"), let k = Int(p.kind.dropFirst(8)) {      // the pick's head points at the soft wall
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5); n.position = pos(Double(p.x) + 0.5, Double(p.y) + 0.5); n.zPosition = 8
                switch k { case 1: n.xScale = -1; case 0: n.zRotation = -.pi / 2; case 3: n.zRotation = .pi / 2; default: break }
            }
            let phase = Double((p.x * 31 + p.y * 17) % 100) / 100
            switch p.kind {
            case "tree":                                                    // a slow sway from the root, each tree out of step
                n.zRotation = -0.025
                n.run(.sequence([.wait(forDuration: phase * 2), .repeatForever(.sequence([.rotate(toAngle: 0.025, duration: 1.8 + phase), .rotate(toAngle: -0.025, duration: 1.8 + phase)]))]))
                for a in [n] { a.run(.repeatForever(.sequence([.scaleY(to: 1.02, duration: 1.4), .scaleY(to: 1, duration: 1.4)]))) }
            case "oldTorch":                                                // grandmother's mist on a stake: teal, slow, never out
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 40, height: 40); g.position = CGPoint(x: 0, y: 19)
                g.color = SKColor(red: 0.45, green: 1, blue: 0.9, alpha: 1); g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0.5; g.zPosition = 12; n.addChild(g)
                g.run(.repeatForever(.sequence([.group([.fadeAlpha(to: 0.85, duration: 1.3 + phase), .scale(to: 1.15, duration: 1.3 + phase)]), .group([.fadeAlpha(to: 0.45, duration: 1.3), .scale(to: 1, duration: 1.3)])])))
            case "lantern":                                                 // a warm flicker on the lamp head
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 30, height: 30); g.position = CGPoint(x: 0, y: 26)
                g.color = SKColor(red: 1, green: 0.85, blue: 0.5, alpha: 1); g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0.5; n.addChild(g)
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.8, duration: 0.3 + phase * 0.3), .fadeAlpha(to: 0.45, duration: 0.5), .fadeAlpha(to: 0.65, duration: 0.2)])))
            case let k where k.hasPrefix("house"):                          // smoke from the chimney, puff by puff
                let top = CGPoint(x: CGFloat(TDArt.houseSize.w) / 2 - 35, y: CGFloat(TDArt.houseSize.h) + 4)
                n.run(.sequence([.wait(forDuration: phase), .repeatForever(.sequence([.run { [weak self, weak n] in
                    guard let self, let n else { return }
                    let puff = SKSpriteNode(texture: TDScene.shadowTex); puff.size = CGSize(width: 8, height: 6); puff.color = SKColor(white: 0.95, alpha: 1); puff.colorBlendFactor = 1
                    puff.alpha = 0.7; puff.position = top; puff.zPosition = 1; n.addChild(puff)
                    puff.run(.sequence([.group([.moveBy(x: CGFloat.random(in: 4...10), y: 26, duration: 2.2), .scale(to: 2.2, duration: 2.2), .fadeOut(withDuration: 2.2)]), .removeFromParent()]))
                    _ = self
                }, .wait(forDuration: 0.7)]))]))
            default: break
            }
        }
    }

    /// Things on the map that glimmer: sparkles on water, a pulse on springs, lamps and stairs.
    func rebuildDecor() {
        decorNode.removeAllChildren()
        let m = game.map
        for y in 0..<m.h { for x in 0..<m.w {
            let t = m.get(x, y), h = (x &* 73856093 ^ y &* 19349663) & 0xffff
            if (t == Tile.water || t == Tile.lava) && h % 5 == 0 {
                let sp = SKSpriteNode(texture: TDScene.dotTex); sp.size = CGSize(width: 5, height: 5); sp.blendMode = .add
                sp.color = t == Tile.water ? SKColor(red: 0.8, green: 0.95, blue: 1, alpha: 1) : SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1); sp.colorBlendFactor = 1
                sp.position = pos(Double(x) + 0.2 + Double(h % 7) / 10, Double(y) + 0.2 + Double(h / 7 % 7) / 10); sp.alpha = 0
                sp.run(.sequence([.wait(forDuration: Double(h % 30) / 10), .repeatForever(.sequence([.fadeAlpha(to: 0.9, duration: 0.25), .fadeOut(withDuration: 0.5), .wait(forDuration: 1.5 + Double(h % 9) / 3)]))]))
                decorNode.addChild(sp)
            }
            if t == Tile.torch {                                           // a torch you set: a warm flicker
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 34, height: 34); g.blendMode = .add; g.zPosition = 21
                g.color = SKColor(red: 1, green: 0.75, blue: 0.4, alpha: 1); g.colorBlendFactor = 1; g.position = pos(Double(x) + 0.5, Double(y) + 0.3); g.alpha = 0.5
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.75, duration: 0.15 + Double(h % 5) / 20), .fadeAlpha(to: 0.45, duration: 0.25), .fadeAlpha(to: 0.6, duration: 0.1)])))
                decorNode.addChild(g)
            }
            if [Tile.lightSpring, Tile.lantern, Tile.stairsDown, Tile.core].contains(t) {
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 40, height: 40); g.blendMode = .add; g.zPosition = 21
                g.color = t == Tile.stairsDown ? SKColor(red: 0.55, green: 1, blue: 0.7, alpha: 1) : SKColor(red: 1, green: 0.9, blue: 0.6, alpha: 1); g.colorBlendFactor = 1
                g.position = pos(Double(x) + 0.5, Double(y) + 0.5); g.alpha = 0.35
                g.run(.repeatForever(.sequence([.group([.fadeAlpha(to: 0.6, duration: 1.1), .scale(to: 1.15, duration: 1.1)]), .group([.fadeAlpha(to: 0.3, duration: 1.1), .scale(to: 1, duration: 1.1)])])))
                decorNode.addChild(g)
            }
        } }
    }

    /// A small puff that drifts and fades on its own.
    func puff(_ x: Double, _ y: Double, _ c: SKColor, size: CGFloat = 4, rise: CGFloat = 6, life: Double = 0.45) {
        let p = SKSpriteNode(texture: TDScene.shadowTex); p.size = CGSize(width: size, height: size * 0.8); p.color = c; p.colorBlendFactor = 1; p.alpha = 0.8
        p.position = pos(x, y); p.zPosition = -18                     // under the light layer, over the floor
        animNode.addChild(p)
        p.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -3...3), y: rise, duration: life), .scale(to: 1.8, duration: life), .fadeOut(withDuration: life)]), .removeFromParent()]))
    }

    /// Fireflies over the village, drifting spores in the caves: a few motes always floating near the camera.
    func spawnMotes(_ dt: Double) {
        moteT -= dt; guard moteT <= 0, animNode.children.count < 70 else { return }
        moteT = 0.25
        let f = game.floor
        let c: SKColor = f == 0 ? SKColor(red: 0.85, green: 1, blue: 0.5, alpha: 1) : (f >= 5 ? { let s = Stage.sky(f).aurora; return SKColor(red: CGFloat(s.0), green: CGFloat(s.1), blue: CGFloat(s.2), alpha: 1) }() : SKColor(red: 0.7, green: 0.9, blue: 1, alpha: 1))
        let m = SKSpriteNode(texture: assets.glow); m.size = CGSize(width: 6, height: 6); m.color = c; m.colorBlendFactor = 1; m.blendMode = .add; m.alpha = 0
        m.position = CGPoint(x: cam.position.x + CGFloat.random(in: -360...360), y: cam.position.y + CGFloat.random(in: -220...220))
        animNode.addChild(m)
        let life = Double.random(in: 3...5)
        m.run(.sequence([.group([
            .sequence([.fadeAlpha(to: 0.9, duration: life * 0.3), .wait(forDuration: life * 0.3), .fadeOut(withDuration: life * 0.4)]),
            .moveBy(x: CGFloat.random(in: -30...30), y: CGFloat.random(in: 8...30), duration: life),
            .repeatForever(.sequence([.scale(to: 1.4, duration: 0.4), .scale(to: 0.8, duration: 0.4)]))]), .removeFromParent()]))
    }

    func uploadLight() {
        let m = game.map, l = game.light()
        var data = [UInt8](repeating: 255, count: m.w * m.h * 4)
        for i in 0..<(m.w * m.h) {
            var r = l.r[i], g = l.g[i], b = l.b[i]
            if m.explored[i] != 0 && game.floor == 0 { r = max(r, 8); g = max(g, 8); b = max(b, 9) }
            data[i * 4] = r &* 17; data[i * 4 + 1] = g &* 17; data[i * 4 + 2] = b &* 17
        }
        let tex = SKTexture(data: Data(data), size: CGSize(width: m.w, height: m.h), flipped: true); tex.filteringMode = .linear
        lightNode.texture = tex; lightNode.size = CGSize(width: m.w * 16, height: m.h * 16); lightNode.position = .zero
    }

    func pos(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * 16, y: -y * 16) }

    func arrived(_ f: Int) {
        mapDirty = true; lightT = 0
        for (_, n) in enemyNodes { n.removeFromParent() }; enemyNodes = [:]
        for (_, n) in dropNodes { n.removeFromParent() }; dropNodes = [:]
        cam.position = pos(game.px, game.py); animNode.removeAllChildren()
        if f == 0 { return }
        if let t = Stage.title(f) { showStage(t.number, t.name, t.line) } else { showStage("\(f)층", L("td.upperName"), L("td.upperLine")) }
        let s = Stage.sky(max(5, f))
        let c = f >= 5 ? SKColor(red: CGFloat(0.7 + s.bottom.0 * 0.3), green: CGFloat(0.7 + s.bottom.1 * 0.3), blue: CGFloat(0.7 + s.bottom.2 * 0.3), alpha: 1) : SKColor(white: 0.92, alpha: 1)
        grade.run(.colorize(with: c, colorBlendFactor: 1, duration: 1.2))
    }

    // MARK: frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, currentTime - lastTime); lastTime = currentTime
        grade.size = CGSize(width: size.width + 4, height: size.height + 4)
        if mapDirty { bake(); uploadLight() }
        guard game.loaded else { return }
        game.input = (keys.contains("a") || keys.contains("left"), keys.contains("d") || keys.contains("right"), keys.contains("w") || keys.contains("up"), keys.contains("s") || keys.contains("down"), keys.contains("k"), keys.contains("space"))
        game.update(dt)
        if mapDirty { bake() }
        lightT -= dt; if lightT <= 0 { lightT = 0.12; uploadLight() }
        let target = pos(game.px, game.py - 0.6)
        cam.position = CGPoint(x: cam.position.x + (target.x - cam.position.x) * min(1, CGFloat(dt) * 8), y: cam.position.y + (target.y - cam.position.y) * min(1, CGFloat(dt) * 8))
        if game.shake > 0 { let a = CGFloat(game.shake) * 22; cam.position.x += CGFloat.random(in: -a...a); cam.position.y += CGFloat.random(in: -a...a) }
        Sound.shared.mood = game.musicMood
        syncEntities(dt); syncLens(dt); spawnMotes(dt); updateHUD(dt)
    }

    func syncEntities(_ dt: Double) {
        let g = game
        // squash and stretch: a little hop in each step, a breath when standing, a squish on the swing and the roll
        var sx: CGFloat = 1, sy: CGFloat = 1, hop: CGFloat = 0
        if g.dodgeT > 0 { sx = 1.25; sy = 0.72 }
        else if g.swing > 0 { let k = CGFloat(g.swing / 0.2); sx = 1 + 0.14 * k; sy = 1 - 0.12 * k }
        else if g.moving { let ph = sin(g.anim * 4 * .pi); hop = CGFloat(abs(ph)) * 2; sy = 1 + 0.05 * CGFloat(abs(ph)); sx = 1 - 0.03 * CGFloat(abs(ph)) }
        else { let b = CGFloat(sin(g.time * 3)); sy = 1 + 0.035 * b; sx = 1 - 0.02 * b }
        if g.iframe > 0.6 && g.dodgeT <= 0 { sx = 0.85; sy = 1.15 }                // flinch when hit
        playerNode.position = pos(g.px, g.py); playerNode.position.y += hop; playerNode.zPosition = 10 + CGFloat(g.py) * 0.01
        // dust from the feet while walking, a burst on the roll
        dustT -= dt
        if (g.moving || g.dodgeT > 0) && dustT <= 0 && g.floor >= 0 { dustT = g.dodgeT > 0 ? 0.04 : 0.22; puff(g.px - g.fx * 0.2, g.py + 0.1, SKColor(white: g.floor == 0 ? 0.9 : 0.75, alpha: 1)) }
        if g.slashT > 0 && lastSwing <= 0 { for _ in 0..<3 { puff(g.px + g.slashX * 1.1, g.py + g.slashY * 1.1 - 0.4, SKColor(red: 1, green: 0.97, blue: 0.85, alpha: 1), size: 3, rise: 4, life: 0.25) } }
        lastSwing = g.slashT
        shadowNode.removeAllChildren()
        func shadow(_ x: Double, _ y: Double, _ w: CGFloat) { let s = SKSpriteNode(texture: TDScene.shadowTex); s.size = CGSize(width: w, height: w * 0.4); s.position = pos(x, y); shadowNode.addChild(s) }
        if g.dead <= 0 { shadow(g.px, g.py + 0.05, 12 - hop) }
        // four directions: down, left, right, up, from the way the player last moved
        let dir = abs(g.fy) > abs(g.fx) ? (g.fy > 0 ? 0 : 3) : (g.fx < 0 ? 1 : 2)
        playerNode.texture = TDArt.shared.walk[dir][g.moving ? Int(g.anim * 8) % 4 : 0]
        playerNode.size = CGSize(width: 16, height: 24); playerNode.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        playerNode.xScale = sx; playerNode.yScale = sy
        playerNode.zRotation = g.dodgeT > 0 ? CGFloat(g.dodgeX > 0 ? -1 : 1) * CGFloat((TDGame.dodgeTime - g.dodgeT) / TDGame.dodgeTime) * .pi * 2 * 0.15 : 0
        playerNode.alpha = g.dead > 0 ? 0 : (g.iframe > 0 && Int(g.iframe * 20) % 2 == 0 ? 0.4 : 1)
        grandmaNode.isHidden = g.floor != 0 || g.disaster
        if !grandmaNode.isHidden {
            let gp = g.map.grandma
            grandmaNode.texture = assets.grandmaFrames[Int(g.anim * 2) % 3]; grandmaNode.position = pos(Double(gp.x) + 0.5, Double(gp.y) + 0.5)
            grandmaNode.zPosition = 10 + CGFloat(gp.y) * 0.01
            let b = CGFloat(sin(g.time * 2.2)); grandmaNode.xScale = (g.px < Double(gp.x) ? -1 : 1) * (1 - 0.02 * b); grandmaNode.yScale = 1 + 0.03 * b
            shadow(Double(gp.x) + 0.5, Double(gp.y) + 0.55, 14)
        }
        var seen = Set<UUID>()
        for e in g.enemies {
            seen.insert(e.id)
            let n = enemyNodes[e.id] ?? { let s = SKSpriteNode(); s.anchorPoint = CGPoint(x: 0.5, y: 0.12); entityNode.addChild(s); enemyNodes[e.id] = s; return s }()
            switch e.kind {
            case .slime: n.texture = assets.slimeFrames[min(2, e.floor / 4)][Int(e.t * 4) % 2]; n.size = CGSize(width: 24, height: 16)
            case .bat: n.texture = assets.batFrames[Int(e.t * 12) % 2]; n.size = CGSize(width: 24, height: 14)
            case .starved: n.texture = assets.zombieFrames[Int(e.t * 8) % 4]; n.size = CGSize(width: 26, height: 28)
            case .lord:
                let fr = assets.lordFrames[e.lordFloor ?? 5] ?? assets.kingFrames
                n.texture = fr[Int(e.t * 3) % fr.count]; n.size = CGSize(width: 72, height: 66)
            }
            // each creature moves its own way: slimes squish, bats bob in the air, the starved sway, lords breathe and shake before a charge
            var sx: CGFloat = 1, sy: CGFloat = 1, lift: CGFloat = 0, rot: CGFloat = 0, shake: CGFloat = 0
            switch e.kind {
            case .slime: let c = CGFloat(cos(e.t * 10)); sx = 1 + 0.16 * c; sy = 1 - 0.16 * c; lift = CGFloat(max(0, sin(e.t * 5))) * 3
            case .bat: lift = 10 + CGFloat(sin(e.t * 6)) * 3
            case .starved: rot = CGFloat(sin(e.t * 4)) * 0.07
            case .lord: let b = CGFloat(sin(e.t * 2)); sy = 1 + 0.03 * b; sx = 1 - 0.015 * b; if g.windingUp(e) { shake = CGFloat(sin(e.t * 60)) * 2 }
            }
            if e.hurt > 0 { let k = CGFloat(e.hurt / 0.2); sx *= 1 + 0.25 * k; sy *= 1 - 0.2 * k }
            n.position = pos(e.x, e.y); n.position.y += lift; n.position.x += shake; n.zPosition = 10 + CGFloat(e.y) * 0.01
            n.xScale = (e.face < 0 ? -1 : 1) * sx; n.yScale = sy; n.zRotation = rot
            shadow(e.x, e.y + 0.05, e.kind == .lord ? 40 : (e.kind == .bat ? 10 - CGFloat(sin(e.t * 6)) * 2 : 14))
            n.colorBlendFactor = e.hurt > 0 ? 0.6 : 0; n.color = .white
        }
        for (k, n) in enemyNodes where !seen.contains(k) { n.removeFromParent(); enemyNodes[k] = nil }
        var seenD = Set<UUID>()
        for d in g.drops {
            seenD.insert(d.uid)
            let n = dropNodes[d.uid] ?? { let s = SKSpriteNode(texture: assets.itemTexture(d.id)); s.size = CGSize(width: 10, height: 10); entityNode.addChild(s); dropNodes[d.uid] = s; return s }()
            n.position = pos(d.x, d.y - 0.3 - 0.1 * sin(d.t * 4)); n.zPosition = 9; n.zRotation = CGFloat(sin(d.t * 3)) * 0.15
            shadow(d.x, d.y + 0.05, 7 + CGFloat(sin(d.t * 4)) * 1.5)
        }
        for (k, n) in dropNodes where !seenD.contains(k) { n.removeFromParent(); dropNodes[k] = nil }
        fxNode.removeAllChildren()
        for p in g.particles { let s = SKSpriteNode(color: SKColor(red: CGFloat(p.color.r) / 255, green: CGFloat(p.color.g) / 255, blue: CGFloat(p.color.b) / 255, alpha: CGFloat(p.t / p.life)), size: CGSize(width: 2, height: 2)); s.position = pos(p.x, p.y); fxNode.addChild(s) }
        drawCombat(g)
        for f in g.floats { let l = SKLabelNode(fontNamed: HUD.fontBold); l.text = f.text; l.fontSize = 8; l.fontColor = SKColor(red: CGFloat(f.color.r) / 255, green: CGFloat(f.color.g) / 255, blue: CGFloat(f.color.b) / 255, alpha: 1); l.position = pos(f.x, f.y); fxNode.addChild(l) }
    }

    /// The swing, the health of what you fight, the lord's warning, and how far a dig has gone. All in the world, no cursor.
    func drawCombat(_ g: TDGame) {
        if g.slashT > 0 {
            let a = atan2(-g.slashY, g.slashX), k = CGFloat(g.slashT / 0.18)
            let path = CGMutablePath(); path.addArc(center: .zero, radius: 20, startAngle: a - 1.1, endAngle: a + 1.1, clockwise: false)
            let arc = SKShapeNode(path: path); arc.strokeColor = SKColor(red: 1, green: 0.97, blue: 0.85, alpha: 0.9 * k); arc.lineWidth = 3; arc.lineCap = .round
            arc.position = pos(g.px, g.py - 0.5); fxNode.addChild(arc)
        }
        for e in g.enemies {
            if e.kind != .lord && e.hp < e.maxhp {
                let w: CGFloat = 18, f = CGFloat(max(0, e.hp)) / CGFloat(e.maxhp)
                let back = SKSpriteNode(color: SKColor(white: 0, alpha: 0.7), size: CGSize(width: w + 2, height: 4)); back.position = pos(e.x, e.y - 1.25); fxNode.addChild(back)
                let fill = SKSpriteNode(color: SKColor(red: 1, green: 0.42, blue: 0.4, alpha: 1), size: CGSize(width: w * f, height: 2)); fill.anchorPoint = CGPoint(x: 0, y: 0.5); fill.position = CGPoint(x: -w / 2, y: 0); back.addChild(fill)
            }
            if g.windingUp(e) {
                let l = SKLabelNode(fontNamed: HUD.fontBold); l.text = "!"; l.fontSize = 18; l.fontColor = SKColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
                l.position = pos(e.x, e.y - 4.6); fxNode.addChild(l)
            }
        }
        if g.mineProg > 0.001, let t = g.mineTarget {
            let back = SKSpriteNode(color: SKColor(white: 0, alpha: 0.7), size: CGSize(width: 16, height: 4)); back.position = pos(Double(t.x) + 0.5, Double(t.y) + 0.5); fxNode.addChild(back)
            let fill = SKSpriteNode(color: SKColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), size: CGSize(width: 14 * CGFloat(min(1, g.mineProg)), height: 2)); fill.anchorPoint = CGPoint(x: 0, y: 0.5); fill.position = CGPoint(x: -7, y: 0); back.addChild(fill)
        }
    }

    func syncLens(_ dt: Double) {
        lensT -= dt; guard lensT <= 0 else { return }; lensT = 0.25
        lensNode.removeAllChildren()
        let pulse = SKAction.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.6), .fadeAlpha(to: 0.95, duration: 0.6)]))
        for m in game.lensMarks() {
            let c: SKColor
            switch m.kind {
            case Tile.gold: c = SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
            case Tile.diamondOre: c = SKColor(red: 0.5, green: 0.95, blue: 1, alpha: 1)
            case Tile.iron: c = SKColor(red: 0.95, green: 0.72, blue: 0.6, alpha: 1)
            case Tile.coal: c = SKColor(white: 0.8, alpha: 1)
            case Tile.crack, Tile.stairsDown, Tile.stairsUp: c = SKColor(red: 0.55, green: 1, blue: 0.6, alpha: 1)
            case Tile.chest, Tile.throne, Tile.core: c = SKColor(red: 1, green: 0.8, blue: 0.35, alpha: 1)
            default: c = SKColor(red: 0.95, green: 1, blue: 0.85, alpha: 1)
            }
            let n = SKSpriteNode(texture: game.lens == .ore ? assets.glow : assets.cursor); n.size = CGSize(width: 16, height: 16)
            n.color = c; n.colorBlendFactor = 1; if game.lens == .ore { n.blendMode = .add }
            n.position = pos(Double(m.x) + 0.5, Double(m.y) + 0.5); n.run(pulse); lensNode.addChild(n)
        }
    }

    // MARK: HUD

    var hw: CGFloat { size.width / 2 }
    var hh: CGFloat { size.height / 2 }

    func lbl(_ l: SKLabelNode, _ s: CGFloat, _ c: SKColor = .white) { l.fontSize = s; l.fontColor = c; l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center }

    func buildHUD() {
        hud.removeAllChildren()
        let hpBack = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: 204, height: 14)); hpBack.anchorPoint = CGPoint(x: 0, y: 0.5); hpBack.name = "hpBack"; hud.addChild(hpBack)
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5); hpFill.position = CGPoint(x: 2, y: 0); hpBack.addChild(hpFill)
        lbl(hpText, 13); hpText.position = CGPoint(x: 212, y: 0); hpBack.addChild(hpText)
        jarIcon.size = CGSize(width: CGFloat(JarArt.w * 2), height: CGFloat(JarArt.h * 2)); jarIcon.name = "jar"; hud.addChild(jarIcon)
        let eBack = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: 124, height: 8)); eBack.anchorPoint = CGPoint(x: 0, y: 0.5); eBack.name = "eBack"; hud.addChild(eBack)
        energyFill.anchorPoint = CGPoint(x: 0, y: 0.5); energyFill.position = CGPoint(x: 2, y: 0); eBack.addChild(energyFill)
        lbl(energyText, 13); energyText.position = CGPoint(x: 132, y: 0); eBack.addChild(energyText)
        let lensRow = SKNode(); lensRow.name = "lensRow"; hud.addChild(lensRow); lensButtons = []
        for m in Lens.allCases {
            let b = SKNode(); b.name = "lens:\(m.rawValue)"
            let bg = SKSpriteNode(color: SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95), size: CGSize(width: 70, height: 22)); bg.name = b.name; b.addChild(bg)
            let l = SKLabelNode(fontNamed: HUD.fontBold); l.text = L(m.titleKey); l.fontSize = 13; l.verticalAlignmentMode = .center; l.name = b.name; b.addChild(l)
            b.position = CGPoint(x: CGFloat(m.rawValue) * 74 + 35, y: 0); lensRow.addChild(b); lensButtons.append(b)
        }
        let tab = SKLabelNode(fontNamed: HUD.fontBold); lbl(tab, 13, SKColor(white: 0.7, alpha: 1)); tab.text = "Tab"; tab.position = CGPoint(x: 226, y: 0); lensRow.addChild(tab)
        let objBack = SKSpriteNode(color: SKColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 0.8), size: CGSize(width: 10, height: 52)); objBack.anchorPoint = CGPoint(x: 0, y: 1); objBack.name = "objBack"; hud.addChild(objBack)
        lbl(objTitle, 15, SKColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)); lbl(objDetail, 13); lbl(progressLabel, 13, SKColor(red: 1, green: 0.85, blue: 0.55, alpha: 1))
        for l in [objTitle, objDetail, progressLabel] { hud.addChild(l) }
        msgLabel.fontSize = 18; msgLabel.numberOfLines = 0; msgLabel.verticalAlignmentMode = .top; msgLabel.preferredMaxLayoutWidth = 820; hud.addChild(msgLabel)
        tipLabel.fontSize = 14; tipLabel.fontColor = SKColor(white: 0.9, alpha: 1); hud.addChild(tipLabel)
        hud.addChild(hotbar); hud.addChild(stage)
        // the creature you are fighting: its name and health, a wide bar for a lord
        let fBack = SKSpriteNode(color: SKColor(white: 0, alpha: 0.65), size: CGSize(width: 324, height: 14)); fBack.name = "fBack"; focusPanel.addChild(fBack)
        focusFill.anchorPoint = CGPoint(x: 0, y: 0.5); focusFill.position = CGPoint(x: -160, y: 0); fBack.addChild(focusFill)
        focusName.fontSize = 15; focusName.verticalAlignmentMode = .bottom; focusName.position = CGPoint(x: 0, y: 10); focusPanel.addChild(focusName)
        focusPanel.alpha = 0; hud.addChild(focusPanel)
        hurtOverlay.alpha = 0; hurtOverlay.zPosition = -1; hud.addChild(hurtOverlay)
        // attack and roll, with their cooldowns filling back in
        combatButtons = []
        for (i, (key, name)) in [("Space", L("td.attack")), ("Shift", L("td.dodge"))].enumerated() {
            let b = SKNode(); b.name = "combat\(i)"
            let bg = SKSpriteNode(color: SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95), size: CGSize(width: 84, height: 46)); b.addChild(bg)
            let shade = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: 84, height: 46)); shade.anchorPoint = CGPoint(x: 0.5, y: 0); shade.position = CGPoint(x: 0, y: -23); shade.yScale = 0; b.addChild(shade)
            let n = SKLabelNode(fontNamed: HUD.fontBold); n.text = name; n.fontSize = 15; n.verticalAlignmentMode = .center; n.position = CGPoint(x: 0, y: 6); b.addChild(n)
            let k = SKLabelNode(fontNamed: HUD.fontMono); k.text = key; k.fontSize = 12; k.fontColor = SKColor(white: 0.7, alpha: 1); k.verticalAlignmentMode = .center; k.position = CGPoint(x: 0, y: -12); b.addChild(k)
            hud.addChild(b); combatButtons.append((b, shade))
        }
        lbl(keysLabel, 13, SKColor(white: 0.75, alpha: 1)); keysLabel.horizontalAlignmentMode = .center; keysLabel.text = L("td.keys"); hud.addChild(keysLabel)
        layoutHUD()
    }

    func layoutHUD() {
        hud.childNode(withName: "hpBack")?.position = CGPoint(x: -hw + 14, y: hh - 20)
        jarIcon.position = CGPoint(x: -hw + 36, y: hh - 62)
        hud.childNode(withName: "eBack")?.position = CGPoint(x: -hw + 62, y: hh - 62)
        hud.childNode(withName: "lensRow")?.position = CGPoint(x: -hw + 60, y: hh - 92)
        hud.childNode(withName: "objBack")?.position = CGPoint(x: -hw + 14, y: hh - 110)
        objTitle.position = CGPoint(x: -hw + 24, y: hh - 126); objDetail.position = CGPoint(x: -hw + 24, y: hh - 148); progressLabel.position = CGPoint(x: -hw + 18, y: hh - 176)
        msgLabel.position = CGPoint(x: 0, y: hh * 0.45 + 20); msgLabel.preferredMaxLayoutWidth = min(820, hw * 2 - 380)
        tipLabel.position = CGPoint(x: 0, y: -hh + 96); hotbar.position = CGPoint(x: -4 * 44 + 22, y: -hh + 34); keysLabel.position = CGPoint(x: 0, y: -hh + 68)
        stage.position = CGPoint(x: 0, y: hh * 0.16)
        focusPanel.position = CGPoint(x: 0, y: hh - 40)
        hurtOverlay.size = CGSize(width: hw * 2 + 4, height: hh * 2 + 4)
        for (i, b) in combatButtons.enumerated() { b.node.position = CGPoint(x: hw - 150 + CGFloat(i) * 92, y: -hh + 40) }
    }
    override func didChangeSize(_ oldSize: CGSize) { if hud.parent != nil { layoutHUD() } }

    func updateHUD(_ dt: Double) {
        let g = game
        hpFill.size.width = 200 * CGFloat(max(0, g.hp)) / CGFloat(g.maxhp); hpText.text = String(format: L("hud.light"), max(0, g.hp), g.maxhp)
        jarIcon.texture = JarArt.texture(g.jar, frame: [0, 1, 2, 1][Int(g.time * 2.2) % 4])
        let ef = CGFloat(g.jar.energy / g.jar.energyCap); energyFill.size.width = 120 * ef
        let jl = g.jar.light
        energyFill.color = SKColor(red: CGFloat(jl.r) / 30 + 0.5, green: CGFloat(jl.g) / 30 + 0.5, blue: CGFloat(jl.b) / 30 + 0.4, alpha: 1)
        energyText.text = String(format: L("energy.hud"), Int(g.jar.energy.rounded()), Int(g.jar.energyCap)) + (g.covered ? " · " + L("td.covered") : "")
        for (i, b) in lensButtons.enumerated() {
            let on = g.lensActive && i == g.lens.rawValue
            (b.children.first as? SKSpriteNode)?.color = on ? SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1) : SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95)
            (b.children.last as? SKLabelNode)?.fontColor = on ? .black : .white; b.alpha = on ? 1 : 0.6
        }
        if let e = g.focus {
            let lord = e.kind == .lord, w: CGFloat = lord ? 320 : 160
            (focusPanel.childNode(withName: "fBack") as? SKSpriteNode)?.size = CGSize(width: w + 4, height: lord ? 14 : 10)
            focusFill.position = CGPoint(x: -w / 2, y: 0); focusFill.size = CGSize(width: w * CGFloat(max(0, e.hp)) / CGFloat(e.maxhp), height: lord ? 10 : 6)
            focusFill.color = lord ? SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1) : SKColor(red: 1, green: 0.42, blue: 0.4, alpha: 1)
            focusName.text = lord ? L("lord.\(e.lordFloor ?? 5).name") : L("td.enemy.\(e.kind)")
            focusName.fontSize = lord ? 18 : 15
            focusPanel.alpha = 1
        } else { focusPanel.alpha = max(0, focusPanel.alpha - CGFloat(dt) * 2) }
        hurtOverlay.alpha = CGFloat(g.hurtFlash / 0.35) * 0.28
        for (i, b) in combatButtons.enumerated() {
            let f = i == 0 ? g.attackCD / TDGame.attackCooldown : g.dodgeCD / TDGame.dodgeCooldown
            b.shade.yScale = CGFloat(max(0, min(1, f)))
            b.node.alpha = (i == 0 ? g.slashT > 0 : g.dodgeT > 0) ? 1 : 0.85
            (b.node.children.first as? SKSpriteNode)?.color = (i == 0 ? g.slashT > 0 : g.dodgeT > 0) ? SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1) : SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95)
        }
        let o = g.objective
        objTitle.text = o.title; objDetail.text = o.detail; progressLabel.text = g.progress
        (hud.childNode(withName: "objBack") as? SKSpriteNode)?.size = CGSize(width: max(objTitle.frame.width, objDetail.frame.width) + 24, height: 52)
        if msgT > 0 { msgT -= dt; msgLabel.alpha = CGFloat(min(1, msgT)) } else if !msgQueue.isEmpty { showMessage(msgQueue.removeFirst()) }
        if tipT > 0 { tipT -= dt; tipLabel.alpha = CGFloat(min(1, tipT)) }
        if g.time.truncatingRemainder(dividingBy: 0.25) < dt { rebuildHotbar() }
    }

    func rebuildHotbar() {
        hotbar.removeAllChildren()
        for i in 0..<8 {
            let s = SKSpriteNode(texture: i == game.sel ? assets.slotSel : assets.slot); s.size = CGSize(width: 40, height: 40); s.position = CGPoint(x: CGFloat(i) * 44, y: 0); hotbar.addChild(s)
            let k = SKLabelNode(fontNamed: HUD.fontMono); k.text = "\(i + 1)"; k.fontSize = 12; k.position = CGPoint(x: -14, y: 8); s.addChild(k)
            if let st = game.inv[i] {
                let ic = SKSpriteNode(texture: assets.itemTexture(st.id)); ic.size = CGSize(width: 24, height: 24); s.addChild(ic)
                if st.n > 1 { let c = SKLabelNode(fontNamed: HUD.fontMono); c.text = "\(st.n)"; c.fontSize = 12; c.horizontalAlignmentMode = .right; c.position = CGPoint(x: 17, y: -16); s.addChild(c) }
            }
        }
    }

    func showMessage(_ t: String) {
        if msgT > 0 && msgLabel.text != t { if !msgQueue.contains(t) && msgQueue.count < 10 { msgQueue.append(t) }; msgT = min(msgT, 2); return }
        msgLabel.text = t; msgT = HUD.readTime(t); msgLabel.alpha = 1
    }
    func showTip(_ t: String) { tipLabel.text = t; tipT = HUD.readTime(t); tipLabel.alpha = 1 }

    func showStage(_ number: String, _ name: String, _ line: String) {
        stage.removeAllActions(); stage.removeAllChildren()
        let a = SKLabelNode(fontNamed: HUD.fontBold); a.text = number; a.fontSize = 18; a.fontColor = SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1); a.position = CGPoint(x: 0, y: 34)
        let b = SKLabelNode(fontNamed: HUD.fontBold); b.text = name; b.fontSize = 36; b.verticalAlignmentMode = .center
        let c = SKLabelNode(fontNamed: HUD.fontBold); c.text = line; c.fontSize = 17; c.fontColor = SKColor(white: 0.85, alpha: 1); c.position = CGPoint(x: 0, y: -40)
        for n in [a, b, c] { stage.addChild(n) }
        stage.alpha = 0
        stage.run(.sequence([.fadeIn(withDuration: 0.7), .wait(forDuration: 3), .fadeOut(withDuration: 1)]))
    }

    // MARK: title

    func showTitle() {
        titleOpen = true; title.removeAllChildren(); title.removeFromParent()
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75), size: CGSize(width: 4000, height: 4000)); title.addChild(dim)
        let t = SKLabelNode(fontNamed: HUD.fontBold); t.text = L("td.title"); t.fontSize = 40; t.position = CGPoint(x: 0, y: 80); title.addChild(t)
        let lines = [L("td.menuNew"), TDGame.hasSave ? L("td.menuContinue") : nil, L("td.menuClassic")].compactMap { $0 }
        for (i, s) in lines.enumerated() { let l = SKLabelNode(fontNamed: HUD.fontBold); l.text = s; l.fontSize = 18; l.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 32); title.addChild(l) }
        title.zPosition = 200; cam.addChild(title)
    }
    func closeTitle() { titleOpen = false; title.removeFromParent() }

    // MARK: input

    private static let keyNames: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 13: "w", 40: "k", 3: "f", 8: "c", 38: "j", 37: "l", 14: "e", 17: "t", 9: "v", 48: "tab", 12: "q",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8",
        123: "left", 124: "right", 126: "up", 125: "down", 36: "return", 76: "return", 49: "space",
    ]

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { if !titleOpen { game.save(); showTitle() }; return }
        guard !event.isARepeat, let c = TDScene.keyNames[event.keyCode] else { return }
        if titleOpen {
            switch c {
            case "return", "space": closeTitle(); game.newGame(); game.onStage = { [weak self] n, name, line in self?.showStage(n, name, line) }; mapDirty = true
            case "c": if TDGame.hasSave, game.load() { closeTitle() }
            case "v": onClassic?()
            default: break
            }
            return
        }
        keys.insert(c)
        switch c {
        case "f": game.feed()
        case "c": game.toggleCover()
        case "tab": game.cycleLens()
        case "j": game.jarLooked = true; showTip(String(format: L("td.jarInfo"), game.jar.stageName, game.jar.colorName, Int(game.jar.energy), Int(game.jar.energyCap)))
        case "t": game.skipErrand()
        case "l": game.dodge()
        case "e": game.placeTorch()
        case "q": game.useHeld()
        case "1", "2", "3", "4", "5", "6", "7", "8": game.sel = Int(c)! - 1; rebuildHotbar()
        default: break
        }
    }
    /// Shift arrives as a modifier change, not a key: roll on the press.
    override func flagsChanged(with event: NSEvent) {
        let down = event.modifierFlags.contains(.shift)
        if down && !shiftDown && !titleOpen { game.dodge() }
        shiftDown = down
    }
    var shiftDown = false

    override func keyUp(with event: NSEvent) { if let c = TDScene.keyNames[event.keyCode] { keys.remove(c) } }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: cam)
        if let name = cam.nodes(at: p).compactMap({ $0.name }).first(where: { $0.hasPrefix("lens:") }), let i = Int(name.dropFirst(5)), let m = Lens(rawValue: i) { game.selectLens(m) }
        else if titleOpen { closeTitle(); game.newGame() }
    }
}
