import Foundation
import AppKit
import SpriteKit

enum PanelKind { case craft, inventory, jar, reign, lore }

/// Screen-space UI built from SpriteKit nodes. `root` is a child of the camera and scaled so 1 unit = 1 point.
final class HUD {
    static let fontBold = "AppleSDGothicNeo-Bold"
    static let fontMono = "Menlo-Bold"

    unowned let scene: GameScene
    let root = SKNode()
    let assets = Assets.shared

    private let heartsNode = SKNode()
    private lazy var vesselFrame = SKSpriteNode(texture: assets.vessel)
    private let vesselFill = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 10))
    private let vesselBack = SKSpriteNode(color: SKColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.85), size: CGSize(width: 1, height: 12))
    private lazy var vesselText = label("", size: 13, color: SKColor(white: 0.9, alpha: 1))
    private let hotbarNode = SKNode()
    private let clock = SKLabelNode(fontNamed: HUD.fontMono)
    private let dayLabel = SKLabelNode(fontNamed: HUD.fontMono)
    private let message = SKLabelNode(fontNamed: HUD.fontBold)
    private let tipLabel = SKLabelNode(fontNamed: HUD.fontBold)
    private var msgQueue: [String] = []
    let hintBar = SKNode()
    let heldLabel = SKLabelNode(fontNamed: HUD.fontBold)
    var shownHints: [KeyHint] = []
    var focusedName: String? = nil
    weak var focusLayer: SKNode? = nil
    var focusRing = SKShapeNode()
    private let objectivePanel = SKSpriteNode(color: SKColor(red: 0.08, green: 0.1, blue: 0.15, alpha: 0.82), size: .zero)
    private let objectiveTitle = SKLabelNode(fontNamed: HUD.fontBold)
    private let objectiveDetail = SKLabelNode(fontNamed: HUD.fontBold)
    private let objectiveSkip = SKLabelNode(fontNamed: HUD.fontBold)
    private let minimap = SKSpriteNode()
    private let minimapFrame = SKSpriteNode()
    private let bossBg = SKSpriteNode(color: .black, size: CGSize(width: 260, height: 14))
    private let bossBar = SKSpriteNode(color: SKColor(red: 0.75, green: 0.45, blue: 1, alpha: 1), size: CGSize(width: 256, height: 10))
    private let bossLabel = SKLabelNode(fontNamed: HUD.fontBold)
    private let breathBg = SKSpriteNode(color: .black, size: CGSize(width: 120, height: 10))
    private let breathBar = SKSpriteNode(color: SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 1), size: CGSize(width: 116, height: 6))
    private let buttons = SKNode()
    var panel: SKNode? = nil
    var panelKind: PanelKind? = nil
    var loreFloor = 5
    var choice: SKNode? = nil
    private let jarIcon = SKSpriteNode()
    private let jarIconGlow = SKSpriteNode()
    private let jarLabel = SKLabelNode(fontNamed: HUD.fontBold)
    private var bugNodes: [SKSpriteNode] = []
    var menu: SKNode? = nil
    private var craftCat = "기본"
    private var msgT = 0.0, tipT = 0.0
    private var minimapData = [UInt8]()
    var inventoryDirty = true
    var showMinimapLarge = false { didSet { layout() } }
    var panelOpen: Bool { panel != nil }
    var hw: CGFloat { scene.size.width / 2 }
    var hh: CGFloat { scene.size.height / 2 }

    init(scene: GameScene) {
        self.scene = scene
        root.zPosition = 1000
        root.addChild(heartsNode); root.addChild(hotbarNode)
        for l in [clock, dayLabel] { l.fontSize = 11; l.horizontalAlignmentMode = .right; l.fontColor = .white; root.addChild(l) }
        message.fontSize = 18; message.fontColor = .white; message.alpha = 0; root.addChild(message)
        // Lords speak in whole scenes, so long lines wrap instead of running off screen.
        message.numberOfLines = 0; message.lineBreakMode = .byWordWrapping; message.verticalAlignmentMode = .top; message.horizontalAlignmentMode = .center
        tipLabel.fontSize = 12; tipLabel.fontColor = SKColor(white: 1, alpha: 0.95); tipLabel.alpha = 0; root.addChild(tipLabel)
        minimapFrame.texture = assets.panel; minimapFrame.centerRect = CGRect(x: 1.0/3, y: 1.0/3, width: 1.0/3, height: 1.0/3)
        root.addChild(minimapFrame); root.addChild(minimap)
        minimap.texture = nil
        bossBg.isHidden = true; bossBar.isHidden = true; bossLabel.isHidden = true
        bossBar.anchorPoint = CGPoint(x: 0, y: 0.5); bossLabel.fontSize = 11; bossLabel.fontColor = .white
        root.addChild(bossBg); root.addChild(bossBar); root.addChild(bossLabel)
        breathBar.anchorPoint = CGPoint(x: 0, y: 0.5); breathBg.isHidden = true; breathBar.isHidden = true
        root.addChild(breathBg); root.addChild(breathBar)
        root.addChild(buttons)
        objectivePanel.anchorPoint = CGPoint(x: 0, y: 1); objectivePanel.isHidden = true; root.addChild(objectivePanel)
        for (l, size, color) in [(objectiveTitle, CGFloat(15), SKColor(red: 1, green: 0.76, blue: 0.3, alpha: 1)), (objectiveDetail, 14, SKColor.white), (objectiveSkip, 13, SKColor(white: 0.75, alpha: 1))] {
            l.fontSize = size; l.fontColor = color; l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
            objectivePanel.addChild(l)
        }
        objectiveSkip.text = L("objective.skip")
        jarIconGlow.texture = assets.glow; jarIconGlow.size = CGSize(width: 90, height: 90); jarIconGlow.colorBlendFactor = 1; jarIconGlow.alpha = 0.5; jarIconGlow.name = "btn:jar"
        jarIcon.texture = assets.jarFrames[0]; jarIcon.size = CGSize(width: 36, height: 40); jarIcon.name = "btn:jar"
        jarLabel.fontSize = 13; jarLabel.fontColor = SKColor(white: 0.85, alpha: 1); jarLabel.horizontalAlignmentMode = .left; jarLabel.verticalAlignmentMode = .center; jarLabel.name = "btn:jar"
        root.addChild(jarIconGlow); root.addChild(jarIcon); root.addChild(jarLabel)
        for (i, (name, symbol, text, key)) in [("btn:craft", "wrench.and.screwdriver", "button.craft", "E"), ("btn:inv", "bag", "button.bag", "I"), ("btn:jar", "sparkles", "button.jar", "J"), ("btn:reign", "crown", "button.reign", "R"), ("btn:map", "map", "button.map", "M"), ("btn:menu", "line.3.horizontal", "button.menu", "ESC")].enumerated() {
            let b = makeKeyButton(symbol: symbol, text: L(text), key: key, name: name)
            b.position = CGPoint(x: 0, y: -CGFloat(i) * 32); buttons.addChild(b)
        }
        hintBar.zPosition = 45; root.addChild(hintBar)
        heldLabel.fontSize = 14; heldLabel.fontColor = .white; heldLabel.verticalAlignmentMode = .center; heldLabel.zPosition = 25; root.addChild(heldLabel)
        layout()
    }

    // MARK: building blocks

    func makePanel(width: CGFloat, height: CGFloat) -> SKSpriteNode {
        let p = SKSpriteNode(texture: assets.panel)
        p.centerRect = CGRect(x: 1.0/3, y: 1.0/3, width: 1.0/3, height: 1.0/3)
        p.size = CGSize(width: width, height: height)
        return p
    }
    func makeButton(_ text: String, name: String, width: CGFloat, height: CGFloat, fontSize: CGFloat = 12, accent: Bool = false, enabled: Bool = true) -> SKNode {
        let n = SKNode(); n.name = name
        let bg = SKSpriteNode(color: accent ? SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1) : SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95), size: CGSize(width: width, height: height))
        bg.name = name
        let border = SKShapeNode(rectOf: CGSize(width: width, height: height)); border.strokeColor = SKColor(white: 0, alpha: 0.9); border.lineWidth = 2; border.name = name
        let l = SKLabelNode(fontNamed: HUD.fontBold); l.text = text; l.fontSize = fontSize; l.verticalAlignmentMode = .center; l.name = name
        l.fontColor = accent ? .black : .white
        n.addChild(bg); n.addChild(border); n.addChild(l)
        if !enabled { n.alpha = 0.4 }
        return n
    }
    func label(_ text: String, size: CGFloat, color: SKColor = .white, font: String = HUD.fontBold, align: SKLabelHorizontalAlignmentMode = .left) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font); l.text = text; l.fontSize = size; l.fontColor = color; l.horizontalAlignmentMode = align; l.verticalAlignmentMode = .center
        return l
    }
    func itemIcon(_ id: Int, size: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(texture: assets.itemTexture(id)); s.size = CGSize(width: size, height: size); return s
    }

    // MARK: layout

    func layout() {
        heartsNode.position = CGPoint(x: -hw + 12, y: hh - 20)
        breathBg.position = CGPoint(x: -hw + 14 + 60, y: hh - 40); breathBar.position = CGPoint(x: -hw + 16, y: hh - 40)
        hotbarNode.position = CGPoint(x: -CGFloat(Game.handSlots - 1) * 22, y: -hh + 30)
        jarIcon.position = CGPoint(x: -hw + 36, y: hh - 86); jarIconGlow.position = jarIcon.position
        jarLabel.position = CGPoint(x: -hw + 60, y: hh - 86)
        clock.position = CGPoint(x: hw - 14, y: hh - 22); dayLabel.position = CGPoint(x: hw - 14, y: hh - 36)
        let ms: CGFloat = showMinimapLarge ? 2.2 : 1.3
        minimap.size = CGSize(width: 120 * ms, height: 66 * ms)
        minimap.position = CGPoint(x: hw - 14 - minimap.size.width / 2, y: hh - 48 - minimap.size.height / 2)
        minimapFrame.size = CGSize(width: minimap.size.width + 8, height: minimap.size.height + 8); minimapFrame.position = minimap.position
        buttons.position = CGPoint(x: hw - 14 - 62, y: minimap.position.y - minimap.size.height / 2 - 24)
        message.position = CGPoint(x: 0, y: hh * 0.45 + 12); message.preferredMaxLayoutWidth = min(900, hw * 2 - 360)
        tipLabel.position = CGPoint(x: 0, y: -hh + 124)
        hintBar.position = CGPoint(x: 0, y: -hh + 70); heldLabel.position = CGPoint(x: 0, y: -hh + 98)
        objectivePanel.position = CGPoint(x: -hw + 14, y: hh - 118)
        bossBg.position = CGPoint(x: 0, y: hh - 30); bossBar.position = CGPoint(x: -128, y: hh - 30); bossLabel.position = CGPoint(x: 0, y: hh - 48)
        panel?.position = .zero; menu?.position = .zero
    }

    // MARK: per-frame

    func update(_ dt: Double, game: Game, zoom: CGFloat) {
        let p = game.player
        // Health is the light the player carries: a glass vessel that grows with light shards and glows in the jar's colour.
        if vesselFrame.parent == nil {
            vesselFrame.anchorPoint = CGPoint(x: 0, y: 0.5); vesselFrame.centerRect = CGRect(x: 6 / 24.0, y: 0.3, width: 12 / 24.0, height: 0.4)
            vesselFill.anchorPoint = CGPoint(x: 0, y: 0.5); vesselFill.zPosition = -1
            vesselBack.anchorPoint = CGPoint(x: 0, y: 0.5); vesselBack.zPosition = -2; vesselBack.position = CGPoint(x: 2, y: 0); heartsNode.addChild(vesselBack)
            vesselText.verticalAlignmentMode = .center
            heartsNode.addChild(vesselFill); heartsNode.addChild(vesselFrame); heartsNode.addChild(vesselText)
        }
        let full = CGFloat(p.maxhp) * 2
        vesselFrame.size = CGSize(width: full + 8, height: 18); vesselBack.size = CGSize(width: full + 4, height: 12)
        let vl = game.jar.light, top = CGFloat(max(1, vl.r, vl.g, vl.b))
        let warm = SKColor(red: 1, green: 0.86, blue: 0.55, alpha: 1)
        let tint = SKColor(red: CGFloat(vl.r) / top, green: CGFloat(vl.g) / top, blue: CGFloat(vl.b) / top, alpha: 1)
        let frac = CGFloat(max(0, p.hp)) / CGFloat(max(1, p.maxhp))
        vesselFill.color = warm.blended(withFraction: 0.55, of: tint) ?? warm
        vesselFill.size = CGSize(width: max(0, (full + 2) * frac), height: 10); vesselFill.position = CGPoint(x: 3, y: 0)
        vesselFill.alpha = frac < 0.3 ? 0.55 + 0.45 * CGFloat(abs(sin(game.storyT * 5))) : 1
        vesselText.text = String(format: L("hud.light"), max(0, p.hp), p.maxhp); vesselText.position = CGPoint(x: full + 16, y: 0)
        breathBg.isHidden = p.breath >= 10; breathBar.isHidden = p.breath >= 10
        breathBar.size.width = 116 * CGFloat(p.breath / 10)
        // clock
        let hh24 = Int(((game.worldTime + 0.25).truncatingRemainder(dividingBy: 1)) * 24)
        let mm = Int(((game.worldTime * 24).truncatingRemainder(dividingBy: 1)) * 60)
        clock.text = String(format: "%02d:%02d", hh24, mm) + " " + (game.night ? "☾" : "☀")
        dayLabel.text = "DAY \(game.day)"
        if let b = game.boss {
            bossBg.isHidden = false; bossBar.isHidden = false; bossLabel.isHidden = false
            bossBar.size.width = 256 * CGFloat(max(0, b.hp)) / CGFloat(b.maxhp); bossLabel.text = game.bossDisplayName
        } else { bossBg.isHidden = true; bossBar.isHidden = true; bossLabel.isHidden = true }
        if msgT > 0 {
            msgT -= dt; message.alpha = CGFloat(min(1, msgT))
            if msgT <= 0, !msgQueue.isEmpty { showMessage(msgQueue.removeFirst()) }
        }
        if tipT > 0 { tipT -= dt; tipLabel.alpha = CGFloat(min(1, tipT)) }
        if inventoryDirty { rebuildHotbar(game); if let k = panelKind { openPanel(k) }; inventoryDirty = false }
        if game.frame % 15 == 0 { renderMinimap(game) }
        buttons.isHidden = menu != nil
        let jl = game.jar.light
        jarIcon.texture = assets.jarFrames[game.jar.stage]
        updateObjective(game)
        updateHints(game)
        jarIconGlow.color = SKColor(red: CGFloat(jl.r) / 15, green: CGFloat(jl.g) / 15, blue: CGFloat(jl.b) / 15, alpha: 1)
        jarIconGlow.alpha = CGFloat(0.25 + Double(game.jar.brightness) / 15 * 0.45) * CGFloat(game.jarDim)
        jarIconGlow.setScale(game.jarNearOre ? 1 + CGFloat(abs(sin(game.storyT * 6))) * 0.25 : 1)
        jarLabel.text = "\(game.jar.colorName)" + (game.jarNearOre ? " · 벌레들이 한쪽으로 몰린다" : (game.jarDim < 0.8 ? " · 빛이 움츠러든다" : ""))
        for (i, b) in bugNodes.enumerated() { b.texture = assets.bugFrames[(game.frame / 6 + i) % 2] }
    }

    /// Sized to its text each frame so the one panel fits every step, in either language.
    private func updateObjective(_ game: Game) {
        guard let o = game.objective else { objectivePanel.isHidden = true; return }
        objectivePanel.isHidden = false
        objectiveTitle.text = o.title; objectiveDetail.text = o.detail
        let showSkip = game.tutorialStep < Tutorial.done && !game.disasterStruck
        objectiveSkip.isHidden = !showSkip
        let width = max(objectiveTitle.frame.width, objectiveDetail.frame.width, showSkip ? objectiveSkip.frame.width : 0) + 24
        objectivePanel.size = CGSize(width: width, height: showSkip ? 82 : 58)
        objectiveTitle.position = CGPoint(x: 12, y: -18); objectiveDetail.position = CGPoint(x: 12, y: -40); objectiveSkip.position = CGPoint(x: 12, y: -62)
    }

    /// Long enough to read at a relaxed pace (Korean, about 8 characters a second).
    static func readTime(_ t: String) -> Double { max(4, Double(t.count) * 0.125 + 1.5) }

    /// Messages wait their turn instead of replacing one still being read; a backlog shortens the wait but never below 2 seconds.
    func showMessage(_ t: String) {
        if msgT > 0 && message.text != t {
            if !msgQueue.contains(t) && msgQueue.count < 6 { msgQueue.append(t) }
            msgT = min(msgT, 2)
            return
        }
        message.text = t; msgT = HUD.readTime(t); message.alpha = 1
    }
    func showTip(_ t: String) { tipLabel.text = t; tipT = HUD.readTime(t); tipLabel.alpha = 1 }

    func rebuildHotbar(_ game: Game) {
        hotbarNode.removeAllChildren()
        for i in 0..<Game.handSlots {
            let sel = i == game.player.sel
            let s = SKSpriteNode(texture: sel ? assets.slotSel : assets.slot); s.size = CGSize(width: 40, height: 40); s.position = CGPoint(x: CGFloat(i) * 44, y: 0); s.name = "hot:\(i)"
            hotbarNode.addChild(s)
            let k = label("\(i + 1)", size: 12, color: SKColor(white: sel ? 1 : 0.8, alpha: 1), font: HUD.fontMono); k.position = CGPoint(x: -17, y: 13); k.name = s.name; k.zPosition = 2; s.addChild(k)
            if let st = game.player.inv[i] {
                let ic = itemIcon(st.id, size: 26); ic.name = s.name; s.addChild(ic)
                if itemStackable(st.id) { let c = label("\(st.n)", size: 12, font: HUD.fontMono, align: .right); c.position = CGPoint(x: 17, y: -13); c.name = s.name; s.addChild(c) }
            }
        }
    }

    func renderMinimap(_ game: Game) {
        let mw = 120, mh = 66
        if minimapData.count != mw * mh * 4 { minimapData = [UInt8](repeating: 0, count: mw * mh * 4) }
        let w = game.world
        let cx = Int(game.player.x) - mw / 2, cy = Int(game.player.y) - mh / 2
        var k = 0
        for y in 0..<mh {
            for x in 0..<mw {
                let wx = cx + x, wy = cy + y
                var r = 0, g = 0, b = 0
                if wx >= 0 && wx < w.w && wy >= 0 && wy < w.h {
                    let i = wy * w.w + wx
                    if w.explored[i] == 0 { r = 8; g = 9; b = 16 }
                    else {
                        let t = Int(w.tiles[i])
                        if t == Tile.air { if wy > w.surface[wx] { r = 40; g = 42; b = 52 } else { r = 80; g = 140; b = 220 } }
                        else { let c = TILES[t].dust; r = c.r; g = c.g; b = c.b }
                    }
                }
                minimapData[k] = UInt8(r); minimapData[k + 1] = UInt8(g); minimapData[k + 2] = UInt8(b); minimapData[k + 3] = 255; k += 4
            }
        }
        func dot(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            for dy in -1...1 { for dx in -1...1 {
                let px = x + dx, py = y + dy
                if px >= 0 && px < mw && py >= 0 && py < mh { let i = (py * mw + px) * 4; minimapData[i] = r; minimapData[i + 1] = g; minimapData[i + 2] = b }
            } }
        }
        for e in game.enemies { dot(Int(e.x) - cx, Int(e.y) - cy, 255, 70, 70) }
        dot(mw / 2, mh / 2, 255, 255, 255)
        let tex = SKTexture(data: Data(minimapData), size: CGSize(width: mw, height: mh), flipped: true)
        tex.filteringMode = .nearest
        minimap.texture = tex
    }

    // MARK: panels

    func togglePanel(_ k: PanelKind) { if panelKind == k { closePanels() } else { openPanel(k) } }
    func closePanels() { panel?.removeFromParent(); panel = nil; panelKind = nil }

    func openPanel(_ k: PanelKind) {
        panel?.removeFromParent()
        let game = scene.game
        if k == .jar { game.jarLooked = true }
        if k == .craft { game.craftOpened = true }
        let n = SKNode(); n.zPosition = 20
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55), size: CGSize(width: hw * 2 + 10, height: hh * 2 + 10)); dim.name = "dim"; n.addChild(dim)
        if k == .craft {
            let bench = game.nearBench()
            let p = makePanel(width: 520, height: 470); n.addChild(p)
            let title = label("CRAFTING", size: 14, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1), font: HUD.fontMono); title.position = CGPoint(x: -240, y: 215); n.addChild(title)
            let note = label(bench ? "작업대 근처 — 모든 레시피 제작 가능" : "작업대(판자 6개)를 설치하고 근처에서 열면 도구·무기·갑옷을 만들 수 있습니다.", size: 11, color: SKColor(white: 0.7, alpha: 1)); note.position = CGPoint(x: -240, y: 195); n.addChild(note)
            for (i, c) in CRAFT_CATS.enumerated() {
                let b = makeButton(c, name: "tab:\(c)", width: 92, height: 24, fontSize: 11, accent: c == craftCat)
                b.position = CGPoint(x: -240 + 46 + CGFloat(i) * 98, y: 168); n.addChild(b)
            }
            var row = 0
            for (ri, r) in RECIPES.enumerated() where r.cat == craftCat {
                let ok = game.canCraft(r, bench: bench)
                let y = 135 - CGFloat(row) * 40
                let bg = SKSpriteNode(color: SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 1), size: CGSize(width: 490, height: 36)); bg.position = CGPoint(x: 0, y: y); bg.name = "craft:\(ri)"; bg.alpha = ok ? 1 : 0.5; n.addChild(bg)
                let ic = itemIcon(r.out, size: 28); ic.position = CGPoint(x: -225, y: y); ic.name = bg.name; n.addChild(ic)
                var extra = ""
                if let it = ITEMS[r.out] { if it.dmg > 0 { extra = " · 공격력 \(it.dmg)" } else if it.armor > 0 { extra = " · 피해 -\(Int(it.armor * 100))%" } }
                let nm = label("\(itemName(r.out)) ×\(r.n)" + (r.bench ? "  (작업대)" : ""), size: 12); nm.position = CGPoint(x: -200, y: y + 8); nm.name = bg.name; n.addChild(nm)
                let ing = r.input.map { "\(itemName($0.0)) \(game.countItem($0.0))/\($0.1)" }.joined(separator: " · ") + extra
                let il = label(ing, size: 10, color: SKColor(white: 0.7, alpha: 1)); il.position = CGPoint(x: -200, y: y - 8); il.name = bg.name; n.addChild(il)
                let b = makeButton("제작", name: "craft:\(ri)", width: 60, height: 26, fontSize: 11, accent: true, enabled: ok); b.position = CGPoint(x: 205, y: y); n.addChild(b)
                row += 1
            }
            let close = makeButton("닫기 [ESC]", name: "close", width: 120, height: 26, fontSize: 11); close.position = CGPoint(x: 0, y: -210); n.addChild(close)
        } else if k == .jar {
            buildJarPanel(into: n, game: game)
        } else if k == .reign {
            buildReignPanel(into: n, game: game)
        } else if k == .lore {
            buildLorePanel(into: n, game: game, floor: loreFloor)
        } else {
            let p = makePanel(width: 420, height: 360); n.addChild(p)
            let title = label("INVENTORY", size: 14, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1), font: HUD.fontMono); title.position = CGPoint(x: -190, y: 160); n.addChild(title)
            let note = label("칸을 고르면 지금 든 손 칸(1~4)과 자리를 바꿉니다. 물약과 빛 조각은 골라서 씁니다.", size: 10, color: SKColor(white: 0.7, alpha: 1)); note.position = CGPoint(x: -190, y: 140); n.addChild(note)
            for i in 0..<40 {
                let sel = i == game.player.sel
                let s = SKSpriteNode(texture: sel ? assets.slotSel : assets.slot); s.size = CGSize(width: 40, height: 40)
                s.position = CGPoint(x: -154 + CGFloat(i % 8) * 44, y: 100 - CGFloat(i / 8) * 44); s.name = "inv:\(i)"; n.addChild(s)
                if let st = game.player.inv[i] {
                    let ic = itemIcon(st.id, size: 26); ic.name = s.name; s.addChild(ic)
                    if itemStackable(st.id) { let c = label("\(st.n)", size: 9, font: HUD.fontMono, align: .right); c.position = CGPoint(x: 17, y: -13); c.name = s.name; s.addChild(c) }
                }
            }
            let ward = max(game.player.armor, game.jar.ward)
            let armorText = "\(game.jar.stageName) · \(game.jar.colorName)  ·  빛의 그릇 \(game.player.maxhp)  ·  캐는 힘 \(String(format: "%.1f", game.jar.digPower))  ·  치는 힘 \(game.jar.strike)" + (ward > 0 ? "  ·  빛이 막는 피해 -\(Int(ward * 100))%" : "")
            let al = label(armorText, size: 11, color: SKColor(white: 0.8, alpha: 1)); al.position = CGPoint(x: -190, y: -122); n.addChild(al)
            let close = makeButton("닫기 [ESC]", name: "close", width: 120, height: 26, fontSize: 11); close.position = CGPoint(x: 0, y: -155); n.addChild(close)
        }
        root.addChild(n); panel = n; panelKind = k
    }

    // MARK: the jar — a second, smaller world

    func buildJarPanel(into n: SKNode, game: Game) {
        let jar = game.jar
        let p = makePanel(width: 560, height: 400); n.addChild(p)
        let title = label(jar.named.uppercased() == jar.named ? "THE JAR" : "병", size: 14, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1), font: HUD.fontMono); title.position = CGPoint(x: -260, y: 180); n.addChild(title)
        let sub = label("\(jar.stageName) · \(jar.colorName) · 밝기 \(jar.brightness)/15", size: 11, color: SKColor(white: 0.7, alpha: 1)); sub.position = CGPoint(x: -260, y: 160); n.addChild(sub)
        // --- the jar itself (left), drawn from its contents
        let jx: CGFloat = -150, jy: CGFloat = -10
        let gw: CGFloat = 150, gh: CGFloat = 220
        let l = jar.light
        let glowCol = SKColor(red: CGFloat(l.r) / 15, green: CGFloat(l.g) / 15, blue: CGFloat(l.b) / 15, alpha: 1)
        let halo = SKSpriteNode(texture: assets.glow); halo.size = CGSize(width: 360, height: 360); halo.position = CGPoint(x: jx, y: jy); halo.color = glowCol; halo.colorBlendFactor = 1; halo.alpha = 0.25 + CGFloat(jar.brightness) / 15 * 0.4; halo.blendMode = .add; n.addChild(halo)
        let glass = SKShapeNode(rect: CGRect(x: jx - gw / 2, y: jy - gh / 2, width: gw, height: gh), cornerRadius: 18)
        glass.fillColor = SKColor(red: 0.75, green: 0.9, blue: 1, alpha: 0.10); glass.strokeColor = SKColor(red: 0.8, green: 0.9, blue: 1, alpha: 0.8); glass.lineWidth = 3; n.addChild(glass)
        let lid = SKSpriteNode(color: SKColor(red: 0.53, green: 0.35, blue: 0.2, alpha: 1), size: CGSize(width: gw - 30, height: 16)); lid.position = CGPoint(x: jx, y: jy + gh / 2 + 6); n.addChild(lid)
        // soil layers: colour from minerals
        let soilH: CGFloat = 60 + CGFloat(jar.iron + jar.gold + jar.diamond) * 4
        let soilBase = SKColor(red: 0.45 + CGFloat(jar.iron) * 0.06, green: 0.3 + CGFloat(jar.gold) * 0.05, blue: 0.2 + CGFloat(jar.diamond) * 0.08, alpha: 1)
        let soil = SKShapeNode(rect: CGRect(x: jx - gw / 2 + 4, y: jy - gh / 2 + 4, width: gw - 8, height: soilH), cornerRadius: 12); soil.fillColor = soilBase; soil.strokeColor = .clear; n.addChild(soil)
        for i in 0..<(jar.iron + jar.gold + jar.diamond) {
            let fleck = SKSpriteNode(texture: assets.pixel); fleck.size = CGSize(width: 4, height: 4); fleck.colorBlendFactor = 1
            fleck.color = i < jar.iron ? SKColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1) : (i < jar.iron + jar.gold ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1) : SKColor(red: 0.5, green: 0.95, blue: 1, alpha: 1))
            fleck.position = CGPoint(x: jx - gw / 2 + 14 + CGFloat((i * 37) % Int(gw - 28)), y: jy - gh / 2 + 10 + CGFloat((i * 23) % Int(soilH - 12))); n.addChild(fleck)
        }
        // water line
        if jar.water > 0.2 {
            let wl = SKShapeNode(rect: CGRect(x: jx - gw / 2 + 4, y: jy - gh / 2 + 4 + soilH, width: gw - 8, height: CGFloat(jar.water) * 2.5)); wl.fillColor = SKColor(red: 0.3, green: 0.55, blue: 0.95, alpha: 0.35); wl.strokeColor = .clear; n.addChild(wl)
        }
        // moss blobs
        let mossN = Int(jar.moss)
        for i in 0..<mossN {
            let m = SKShapeNode(circleOfRadius: 6 + CGFloat(i % 3) * 2); m.fillColor = SKColor(red: 0.25, green: 0.6 + CGFloat(l.g) / 60, blue: 0.3, alpha: 0.9); m.strokeColor = .clear
            m.position = CGPoint(x: jx - gw / 2 + 16 + CGFloat((i * 41) % Int(gw - 32)), y: jy - gh / 2 + 6 + soilH + CGFloat((i * 13) % 10)); n.addChild(m)
        }
        // spore plants
        let plants: [(Bool, Int)] = [(jar.sporeR, Tile.redPlant), (jar.sporeG, Tile.greenPlant), (jar.sporeB, Tile.bluePlant)]
        var px: CGFloat = jx - 40
        for (has, tile) in plants where has {
            let sp = itemIcon(tile, size: 40); sp.position = CGPoint(x: px, y: jy - gh / 2 + soilH + 24); n.addChild(sp)
            let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 90, height: 90); g.position = sp.position; g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0.35
            g.color = tile == Tile.redPlant ? SKColor(red: 1, green: 0.3, blue: 0.4, alpha: 1) : (tile == Tile.greenPlant ? SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1) : SKColor(red: 0.4, green: 0.7, blue: 1, alpha: 1)); n.addChild(g)
            px += 40
        }
        // bugs
        bugNodes = []
        for i in 0..<jar.gel {
            let b = SKSpriteNode(texture: assets.bugFrames[0]); b.size = CGSize(width: 8, height: 8); b.colorBlendFactor = 1; b.color = glowCol
            b.position = CGPoint(x: jx + CGFloat.random(in: -50...50), y: jy + CGFloat.random(in: -40...80))
            let wander = SKAction.repeatForever(SKAction.sequence([
                SKAction.move(to: CGPoint(x: jx + CGFloat.random(in: -55...55), y: jy + CGFloat.random(in: -30...90)), duration: Double.random(in: 1.2...2.4)),
                SKAction.move(to: CGPoint(x: jx + CGFloat.random(in: -55...55), y: jy + CGFloat.random(in: -30...90)), duration: Double.random(in: 1.2...2.4))]))
            b.run(wander); n.addChild(b); bugNodes.append(b); _ = i
        }
        // --- right: what it does, and what you can feed it
        var y: CGFloat = 130
        let facts = ["빨강 \(l.r)  초록 \(l.g)  파랑 \(l.b)",
                     jar.isRed ? "붉은빛: 벽 속 광맥이 비친다 · 용암 옆에 설 수 있다" : "붉은 포자 + 철 → 붉은빛 (광맥을 드러냄)",
                     jar.isGreen ? "초록빛: 덩굴이 자란다 · 숨은 식물이 보인다" : "초록 포자 + 금 → 초록빛 (덩굴·식물)",
                     jar.isBlue ? "푸른빛: 물의 장막을 지난다 · 물속이 보인다" : "푸른 포자 + 다이아 + 물 → 푸른빛 (물의 장막)",
                     jar.isViolet ? "보랏빛: 유령 돌이 열린다" : "빨강 + 파랑 → 보랏빛 (유령 돌)",
                     jar.isWhite ? "흰빛: 모든 것이 보인다 — 그리고 모든 것이 당신을 본다" : "셋 다 밝히면 흰빛 — 심장이 응답한다"]
        for f in facts { let fl = label(f, size: 11, color: SKColor(white: 0.82, alpha: 1)); fl.position = CGPoint(x: 0, y: y); n.addChild(fl); y -= 20 }
        y -= 6
        let fh = label("넣기 (F = 손에 든 것):", size: 11, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1)); fh.position = CGPoint(x: 0, y: y); n.addChild(fh); y -= 24
        var shown = 0
        for (i, st) in game.player.inv.enumerated() {
            guard let s = st, jar.acceptReason(s.id) == nil, shown < 5 else { continue }
            let b = makeButton("\(itemName(s.id)) ×\(s.n)", name: "feed:\(i)", width: 170, height: 24, fontSize: 11)
            b.position = CGPoint(x: 85 + CGFloat(shown % 2) * 180, y: y - CGFloat(shown / 2) * 30); n.addChild(b); shown += 1
        }
        if shown == 0 { let none = label("넣을 수 있는 것이 없다. 광석·포자·젤을 찾아보자.", size: 11, color: SKColor(white: 0.6, alpha: 1)); none.position = CGPoint(x: 0, y: y); n.addChild(none) }
        let close = makeButton("닫기 [ESC]", name: "close", width: 120, height: 26, fontSize: 11); close.position = CGPoint(x: 160, y: -170); n.addChild(close)
    }

    func showChoice() {
        choice?.removeFromParent()
        let n = SKNode(); n.zPosition = 40
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.7), size: CGSize(width: 4000, height: 4000)); dim.name = "dim"; n.addChild(dim)
        let p = makePanel(width: 560, height: 300); n.addChild(p)
        let t = label("빛의 심장이 깨어났다", size: 18, color: SKColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), align: .center); t.position = CGPoint(x: 0, y: 110); n.addChild(t)
        let lines = ["그들은 빛기둥을 깨고 하늘로 오르던 빛을 여기 붙잡았다. 그래서 위는 어두워졌고, 아래는 밝아졌다.",
                     "빛을 위로 돌려보내면 기둥이 이어져 무너진 암석이 부서지고, 올라가는 길이 열린다. 캠프 사람들이 따라올 것이다.",
                     "빛을 여기 남기면 지하 도시가 새 집이 된다. 하늘은 꺼진 채로."]
        for (i, s) in lines.enumerated() { let l = label(s, size: 11.5, color: SKColor(white: 0.8, alpha: 1), align: .center); l.position = CGPoint(x: 0, y: 70 - CGFloat(i) * 22); n.addChild(l) }
        let up = makeButton("빛을 위로 돌려보낸다 — 하늘을 되찾는다", name: "choice:up", width: 420, height: 36, fontSize: 13, accent: true); up.position = CGPoint(x: 0, y: -30); n.addChild(up)
        let stay = makeButton("빛을 여기 남긴다 — 지하에 산다", name: "choice:stay", width: 420, height: 36, fontSize: 13); stay.position = CGPoint(x: 0, y: -80); n.addChild(stay)
        root.addChild(n); choice = n
    }

    // MARK: menu

    func showMenu(hasSave: Bool) {
        menu?.removeFromParent()
        let n = SKNode(); n.zPosition = 30
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: 4000, height: 4000)); dim.name = "dim"; n.addChild(dim)
        let p = makePanel(width: 520, height: 420); n.addChild(p)
        let t = label("PIXEL EARTH", size: 30, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1), font: HUD.fontMono, align: .center); t.position = CGPoint(x: 0, y: 160); n.addChild(t)
        let shadow = label("PIXEL EARTH", size: 30, color: .black, font: HUD.fontMono, align: .center); shadow.position = CGPoint(x: 3, y: 157); shadow.zPosition = -1; n.addChild(shadow)
        let s1 = label("별을 잃은 행성 나엘. 하늘의 마지막 빛을 병에 담아 들고 땅속으로 내려가,", size: 12, color: SKColor(white: 0.75, alpha: 1), align: .center); s1.position = CGPoint(x: 0, y: 122); n.addChild(s1)
        let s2 = label("그 빛을 키워 하늘을 되찾는 이야기.", size: 12, color: SKColor(white: 0.75, alpha: 1), align: .center); s2.position = CGPoint(x: 0, y: 104); n.addChild(s2)
        var y: CGFloat = 60
        if hasSave { let b = makeButton("이어하기", name: "menu:continue", width: 300, height: 36, fontSize: 14, accent: true); b.position = CGPoint(x: 0, y: y); n.addChild(b); y -= 46 }
        let nb = makeButton("새 세계 만들기", name: "menu:new", width: 300, height: 36, fontSize: 14, accent: !hasSave); nb.position = CGPoint(x: 0, y: y); n.addChild(nb); y -= 46
        let sb = makeButton("소리: " + (Sound.shared.enabled ? "켬" : "끔"), name: "menu:sound", width: 145, height: 30, fontSize: 12); sb.position = CGPoint(x: -78, y: y); n.addChild(sb)
        let zb = makeButton("확대: " + ["작게", "보통", "크게"][scene.zoomIndex], name: "menu:zoom", width: 145, height: 30, fontSize: 12); zb.position = CGPoint(x: 78, y: y); n.addChild(zb); y -= 40
        let help = ["이동 A/D · 점프 SPACE · 위아래 보기 W/S · 발판 내려가기 S · 핫바 1~9",
                    "K 공격·캐기·사용 · L 설치 · Q 버리기 · 마우스도 쓸 수 있습니다",
                    "E 제작 · I 가방 · J 병 · F 병에 넣기 · R 왕좌 · M 지도 · ESC 메뉴/저장",
                    "병에 포자와 광석을 넣으면 빛의 색이 바뀌고, 색에 따라 세계가 다르게 보입니다",
                    "붉은빛은 광맥을, 푸른빛은 물의 장막을, 보랏빛은 유령 돌을, 흰빛은 심장을 엽니다"]
        for (i, h) in help.enumerated() { let l = label(h, size: 10.5, color: SKColor(white: 0.65, alpha: 1), align: .center); l.position = CGPoint(x: 0, y: y - CGFloat(i) * 17); n.addChild(l) }
        root.addChild(n); menu = n
    }
    func hideMenu() { menu?.removeFromParent(); menu = nil }
    func refreshMenu() { if menu != nil { showMenu(hasSave: scene.game.loaded || SaveStore.exists()) } }

    // MARK: clicks

    /// Returns true when the click was consumed by UI.
    func handleClick(scenePoint: CGPoint) -> Bool {
        let p = root.convert(scenePoint, from: scene)
        let hits = root.nodes(at: p)
        guard let named = hits.sorted(by: { $0.zPosition > $1.zPosition }).first(where: { $0.name != nil && $0.name != "dim" && $0.name != "heart" }) ?? hits.first(where: { $0.name == "dim" }),
              let name = named.name else { return menu != nil || panel != nil || choice != nil }
        return perform(name)
    }

    func perform(_ name: String) -> Bool {
        let game = scene.game
        let parts = name.split(separator: ":").map(String.init)
        switch parts[0] {
        case "menu":
            switch parts[1] {
            case "new": scene.startNew()
            case "continue": scene.continueGame()
            case "sound": Sound.shared.enabled.toggle(); refreshMenu(); if Sound.shared.enabled { Sound.shared.play(.pick) }
            case "zoom": scene.zoomIndex = (scene.zoomIndex + 1) % 3; refreshMenu()
            default: break
            }
            return true
        case "btn":
            if menu != nil { return true }
            switch parts[1] {
            case "craft": togglePanel(.craft)
            case "inv": togglePanel(.inventory)
            case "jar": togglePanel(.jar)
            case "reign": togglePanel(.reign)
            case "map": showMinimapLarge.toggle()
            case "menu": scene.openMenu()
            default: break
            }
            return true
        case "close": closePanels(); return true
        case "lore":
            if parts[1] == "back" { openPanel(.reign) } else if let f = Int(parts[1]) { loreFloor = f; openPanel(.lore) }
            return true
        case "feed":
            if let i = Int(parts[1]) { game.feedJar(slot: i); openPanel(.jar) }
            return true
        case "choice":
            choice?.removeFromParent(); choice = nil
            game.chooseEnding(up: parts[1] == "up")
            return true
        case "tab": craftCat = parts[1]; openPanel(.craft); return true
        case "craft":
            if let i = Int(parts[1]) { game.craft(RECIPES[i]); openPanel(.craft) }
            return true
        case "hot":
            if let i = Int(parts[1]) { scene.selectSlot(i) }
            return true
        case "inv":
            if let i = Int(parts[1]) {
                if let s = game.player.inv[i], ITEMS[s.id]?.use != nil, game.useItem(slot: i) { openPanel(.inventory); return true }
                let tmp = game.player.inv[game.player.sel]; game.player.inv[game.player.sel] = game.player.inv[i]; game.player.inv[i] = tmp
                inventoryDirty = true; openPanel(.inventory)
            }
            return true
        case "dim":
            return true
        default:
            return menu != nil || panel != nil || choice != nil
        }
    }
}

// MARK: - key hints

extension HUD {
    private static var symbolCache: [String: SKTexture] = [:]

    /// A white SF Symbol as a texture, drawn at 2x so it stays sharp on Retina.
    static func symbolTexture(_ name: String) -> SKTexture? {
        if let t = symbolCache[name] { return t }
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        let white = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect); NSColor.white.set(); rect.fill(using: .sourceIn); return true
        }
        let t = SKTexture(image: white)
        symbolCache[name] = t
        return t
    }

    private func symbolNode(_ name: String, height: CGFloat, color: SKColor) -> SKSpriteNode? {
        guard let t = HUD.symbolTexture(name) else { return nil }
        let s = SKSpriteNode(texture: t)
        s.size = CGSize(width: height * t.size().width / max(1, t.size().height), height: height)
        s.color = color; s.colorBlendFactor = 1
        return s
    }

    /// A keyboard key drawn as a raised cap, positioned by its centre.
    private func keyCap(_ key: String, urgent: Bool, name: String? = nil) -> SKNode {
        let n = SKNode()
        let text = label(key, size: 13, color: urgent ? .black : SKColor(red: 0.1, green: 0.12, blue: 0.17, alpha: 1), align: .center)
        let width = max(22, text.frame.width + 12)
        let cap = SKShapeNode(rectOf: CGSize(width: width, height: 22), cornerRadius: 5)
        cap.fillColor = urgent ? SKColor(red: 1, green: 0.76, blue: 0.3, alpha: 1) : SKColor(white: 0.92, alpha: 1)
        cap.strokeColor = SKColor(white: 0, alpha: 0.75); cap.lineWidth = 1.5
        cap.name = name; text.name = name
        n.addChild(cap); n.addChild(text); n.name = name
        return n
    }
    private func keyCapWidth(_ key: String) -> CGFloat {
        max(22, label(key, size: 13).frame.width + 12)
    }

    /// Right-column button: symbol, label, and the key that does the same thing.
    func makeKeyButton(symbol: String, text: String, key: String, name: String) -> SKNode {
        let n = SKNode(); n.name = name
        let bg = SKSpriteNode(color: SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 0.95), size: CGSize(width: 124, height: 28)); bg.name = name; n.addChild(bg)
        if let s = symbolNode(symbol, height: 15, color: .white) { s.position = CGPoint(x: -48, y: 0); s.name = name; n.addChild(s) }
        let l = label(text, size: 13); l.position = CGPoint(x: -34, y: 0); l.name = name; n.addChild(l)
        let cap = keyCap(key, urgent: false, name: name); cap.position = CGPoint(x: 58 - keyCapWidth(key) / 2, y: 0); n.addChild(cap)
        return n
    }

    /// Rebuilt only when the hints change: shape nodes are too costly to remake every frame.
    func updateHints(_ game: Game) {
        let hidden = menu != nil || choice != nil
        hintBar.isHidden = false; heldLabel.isHidden = hidden || panelOpen
        updateFocusRing()
        if let s = game.player.held { heldLabel.text = String(format: L("hint.holding"), itemName(s.id)) }
        else { heldLabel.text = L("hint.holdingNone") }
        let hints = game.keyHints(panel: panelKind, modal: hidden)
        if hints == shownHints { return }
        shownHints = hints
        hintBar.removeAllChildren()
        var items: [(node: SKNode, width: CGFloat)] = []
        for h in hints {
            let item = SKNode(); var x: CGFloat = 8
            if let s = symbolNode(h.symbol, height: 14, color: h.urgent ? SKColor(red: 1, green: 0.76, blue: 0.3, alpha: 1) : .white) {
                s.position = CGPoint(x: x + s.size.width / 2, y: 0); item.addChild(s); x += s.size.width + 6
            }
            let capW = keyCapWidth(h.key)
            let cap = keyCap(h.key, urgent: h.urgent); cap.position = CGPoint(x: x + capW / 2, y: 0); item.addChild(cap); x += capW + 6
            let l = label(h.text, size: 13, color: h.urgent ? SKColor(red: 1, green: 0.85, blue: 0.5, alpha: 1) : .white); l.position = CGPoint(x: x, y: 0); item.addChild(l); x += l.frame.width + 8
            let bg = SKSpriteNode(color: SKColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.78), size: CGSize(width: x, height: 28))
            bg.position = CGPoint(x: x / 2, y: 0); bg.zPosition = -1; item.addChild(bg)
            if h.urgent { item.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]))) }
            items.append((item, x))
        }
        var x = -(items.reduce(0) { $0 + $1.width } + CGFloat(max(0, items.count - 1)) * 6) / 2
        for it in items { it.node.position = CGPoint(x: x, y: 0); hintBar.addChild(it.node); x += it.width + 6 }
    }
}

// MARK: - keyboard navigation

extension HUD {
    var modalOpen: Bool { menu != nil || choice != nil }
    private var activeLayer: SKNode? { choice ?? menu ?? panel }
    private static let focusPrefixes = ["menu:", "choice:", "close", "tab:", "craft:", "inv:", "feed:", "lore:"]

    /// Everything in the open window that can be chosen, keyed by its action name.
    private func focusables() -> [(name: String, rect: CGRect)] {
        guard let layer = activeLayer else { return [] }
        var found: [String: CGRect] = [:], order: [String] = []
        func walk(_ n: SKNode) {
            if let name = n.name, HUD.focusPrefixes.contains(where: { name.hasPrefix($0) }) {
                let f = n.calculateAccumulatedFrame()
                let r = CGRect(origin: root.convert(f.origin, from: n.parent ?? root), size: f.size)
                if let old = found[name] { found[name] = old.union(r) } else { found[name] = r; order.append(name) }
            }
            for c in n.children { walk(c) }
        }
        walk(layer)
        return order.map { ($0, found[$0]!) }
    }

    /// WASD or arrows move, K, Return or Space choose. Returns true if the key was used.
    func handleNavKey(_ c: String) -> Bool {
        let move: (x: CGFloat, y: CGFloat)?
        switch c {
        case "w", "up": move = (0, 1)
        case "s", "down": move = (0, -1)
        case "a", "left": move = (-1, 0)
        case "d", "right": move = (1, 0)
        case "k", "return", "space":
            if let f = focusedName ?? focusables().first?.name { _ = perform(f); focusLayer = nil }
            return true
        default: return modalOpen
        }
        let items = focusables()
        guard let m = move, let cur = items.first(where: { $0.name == focusedName }) ?? items.first else { return true }
        var best: String? = nil, bestCost = CGFloat.infinity
        for it in items where it.name != cur.name {
            let dx = it.rect.midX - cur.rect.midX, dy = it.rect.midY - cur.rect.midY
            let along = dx * m.x + dy * m.y
            if along <= 1 { continue }
            let cost = along + abs(dx * m.y - dy * m.x) * 2.5
            if cost < bestCost { bestCost = cost; best = it.name }
        }
        if let b = best { focusedName = b; focusLayer = nil; scene.game.sfx(.pick) }
        return true
    }

    /// Follows windows being rebuilt: keeps the same action selected, or starts at the first one.
    func updateFocusRing() {
        guard let layer = activeLayer else { focusRing.removeFromParent(); focusLayer = nil; focusedName = nil; return }
        if focusLayer === layer { return }
        focusLayer = layer
        let items = focusables()
        if !items.contains(where: { $0.name == focusedName }) {
            focusedName = panelKind == .inventory && choice == nil && menu == nil ? "inv:\(scene.game.player.sel)" : items.first?.name
        }
        focusRing.removeFromParent()
        guard let r = items.first(where: { $0.name == focusedName })?.rect else { return }
        let ring = SKShapeNode(rect: r.insetBy(dx: -3, dy: -3), cornerRadius: 4)
        ring.strokeColor = SKColor(red: 1, green: 0.76, blue: 0.3, alpha: 1); ring.lineWidth = 3; ring.fillColor = .clear; ring.zPosition = 44
        focusRing = ring; root.addChild(ring)
    }

    func buildReignPanel(into n: SKNode, game: Game) {
        let p = makePanel(width: 740, height: 400); n.addChild(p)
        let title = label(L("reign.title"), size: 16, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1)); title.position = CGPoint(x: -300, y: 160); n.addChild(title)
        let note = label(L("reign.note") + " " + L("reign.storyNote"), size: 13, color: SKColor(white: 0.75, alpha: 1)); note.position = CGPoint(x: -340, y: 134); n.addChild(note)
        title.position.x = -340
        for (i, r) in game.reigns.enumerated() {
            let y = 92 - CGFloat(i) * 46
            let bg = SKSpriteNode(color: SKColor(red: 0.16, green: 0.19, blue: 0.27, alpha: r.state == .player ? 1 : 0.7), size: CGSize(width: 700, height: 40)); bg.position = CGPoint(x: 0, y: y); n.addChild(bg)
            let c = Reign.tint(r.floor)
            if let s = HUD.symbolTexture("crown") {
                let ic = SKSpriteNode(texture: s); ic.size = CGSize(width: 22, height: 18); ic.position = CGPoint(x: -328, y: y); ic.color = SKColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1); ic.colorBlendFactor = 1; ic.alpha = r.state == .vacant ? 0.3 : 1; n.addChild(ic)
            }
            let name = label(game.floorName(r.floor), size: 14); name.position = CGPoint(x: -308, y: y + 9); n.addChild(name)
            let owner: String
            switch r.state {
            case .lord: owner = game.lordName(r) + " · " + String(format: L("reign.power"), Reign.hp(r.floor, generation: r.generation), Reign.damage(r.floor, generation: r.generation))
            case .vacant: owner = String(format: L("reign.statusVacant"), Int(r.vacantT))
            case .player:
                let next = DefenseDesign.level(floor: r.floor, defenses: r.defenses)
                owner = String(format: L("reign.statusPlayer"), r.generation, r.defenses, r.tribute.values.reduce(0, +)) + " · " + String(format: L("reign.nextLevel"), next, L("defense.tier.\(DefenseDesign.tier(next))"))
            }
            let ol = label(owner, size: 13, color: SKColor(white: 0.8, alpha: 1)); ol.position = CGPoint(x: -308, y: y - 9); n.addChild(ol)
            let met = game.meetsClaimCondition(r.floor)
            let cond = label(L("floor.\(r.floor).light") + (met ? " ✓" : ""), size: 13, color: met ? SKColor(red: 0.5, green: 0.95, blue: 0.55, alpha: 1) : SKColor(white: 0.6, alpha: 1), align: .right); cond.position = CGPoint(x: 250, y: y); n.addChild(cond)
            let story = makeButton(L("reign.story") + (r.truthKnown == true ? " ✦" : ""), name: "lore:\(r.floor)", width: 74, height: 28, fontSize: 13); story.position = CGPoint(x: 302, y: y); n.addChild(story)
        }
        let close = makeButton(L("hint.close") + " [ESC]", name: "close", width: 120, height: 28, fontSize: 13); close.position = CGPoint(x: 0, y: -172); n.addChild(close)
    }

    /// One floor's lord: the rumour everyone knows, and once a lord there is beaten, what really happened.
    func buildLorePanel(into n: SKNode, game: Game, floor f: Int) {
        let p = makePanel(width: 640, height: 520); n.addChild(p)
        let c = Reign.tint(f), tint = SKColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
        let title = label(game.floorName(f) + " · " + L("lord.\(f).name"), size: 18, color: tint); title.position = CGPoint(x: -290, y: 230); n.addChild(title)
        var y: CGFloat = 198
        func section(_ head: String, _ body: String, color: SKColor = SKColor(white: 0.88, alpha: 1)) {
            let h = label(head, size: 14, color: SKColor(red: 1, green: 0.7, blue: 0.24, alpha: 1)); h.position = CGPoint(x: -290, y: y); n.addChild(h); y -= 14
            let b = label(body, size: 14, color: color); b.numberOfLines = 0; b.preferredMaxLayoutWidth = 580; b.lineBreakMode = .byWordWrapping
            b.verticalAlignmentMode = .top; b.position = CGPoint(x: -290, y: y); n.addChild(b)
            y -= b.frame.height + 18
        }
        let r = game.reignIndex(f).map { game.reigns[$0] }
        section(L("lore.rumor"), L("lord.\(f).rumor"))
        if r?.truthKnown == true {
            section(L("lore.truth"), L("lord.\(f).truth"))
            section(L("lore.creed"), L("lord.\(f).creed") + "\n" + L("lord.\(f).last"), color: SKColor(white: 0.75, alpha: 1))
        } else {
            section(L("lore.truth"), L("lore.locked"), color: SKColor(white: 0.55, alpha: 1))
        }
        if let r = r {
            if r.state == .player { section(String(format: L("lore.current"), L("reign.you")), L("lore.you")) }
            else if r.state == .lord && r.generation > 1 { section(String(format: L("lore.current"), game.lordName(r)), game.lordCreed(r)) }
        }
        let back = makeButton(L("lore.back"), name: "lore:back", width: 130, height: 28, fontSize: 13); back.position = CGPoint(x: -75, y: -232); n.addChild(back)
        let close = makeButton(L("hint.close") + " [ESC]", name: "close", width: 130, height: 28, fontSize: 13); close.position = CGPoint(x: 75, y: -232); n.addChild(close)
    }
}
