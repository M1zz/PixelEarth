import Foundation
import SpriteKit
import AppKit

final class GameScene: SKScene {
    let game = Game()
    let assets = Assets.shared
    var chunkRenderer: ChunkRenderer!
    let cam = SKCameraNode()
    let worldNode = SKNode()
    let entityNode = SKNode()
    let fxNode = SKNode()
    let bgNode = SKNode()
    var hud: HUD!
    var zoom: CGFloat = 2
    var zoomIndex = 1 { didSet { zoom = [1.5, 2, 3][zoomIndex]; applyZoom() } }

    // background pieces
    var skyNode = SKSpriteNode()
    var starsNode = SKSpriteNode()
    var moonNode = SKSpriteNode()
    var mountainsA: [SKSpriteNode] = [], mountainsB: [SKSpriteNode] = []
    /// Skymist: the sky is drawn by a shader (gradient + moving aurora curtains), quantized to chunky pixels.
    let skyUniforms = (day: SKUniform(name: "u_day", float: 1), dusk: SKUniform(name: "u_dusk", float: 0),
                       under: SKUniform(name: "u_under", float: 0), cam: SKUniform(name: "u_cam", float: 0),
                       res: SKUniform(name: "u_res", vectorFloat2: vector_float2(800, 600)),
                       stage: SKUniform(name: "u_stage", float: 0), stop: SKUniform(name: "u_stop", vectorFloat4: vector_float4(0, 0, 0, 0)),
                       sbot: SKUniform(name: "u_sbot", vectorFloat4: vector_float4(0, 0, 0, 0)), saur: SKUniform(name: "u_saur", vectorFloat4: vector_float4(0, 0, 0, 0)))
    /// The stage sky shown now, eased toward the floor the player is on so arriving reads as a new sky opening.
    var stageSky: (top: SIMD3<Float>, bot: SIMD3<Float>, aur: SIMD4<Float>, blend: Float, stars: Float) = (.zero, .zero, .zero, 0, 0)
    var lastStageShown: Int? = nil
    /// Light rises from below on Nael: slow motes drift upward around the player, tinted by the floor's light.
    let motes = SKEmitterNode()

    // lighting
    let lightSprite = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
    var lightData = [UInt8]()
    var lightRect = (x0: 0, y0: 0, x1: -1, y1: -1)

    // entities
    let playerNode = SKNode()
    let playerBody = SKSpriteNode()
    let armNode = SKSpriteNode()
    let heldNode = SKSpriteNode()
    var enemyNodes: [UUID: SKSpriteNode] = [:]
    var dropNodes: [UUID: SKSpriteNode] = [:]
    var arrowNodes: [UUID: SKSpriteNode] = [:]
    var floatNodes: [UUID: SKLabelNode] = [:]
    var particleNodes: [SKSpriteNode] = []
    let cursorNode = SKSpriteNode()
    var digKick: CGFloat = 0    // 1 on a strike, fading: jolts the body and the block
    let crownNode = SKSpriteNode()
    var turretNodes: [SKSpriteNode] = []
    let crackNode = SKSpriteNode()
    let placeGhost = SKSpriteNode()     // keyboard play: where L will put the held block
    /// Each floor below has one color of its own; everything is multiplied by it, so a floor reads at a glance.
    let gradeNode = SKSpriteNode(color: .white, size: CGSize(width: 4000, height: 4000))
    private var grade = (r: CGFloat(1), g: CGFloat(1), b: CGFloat(1))

    // story / light-gate visuals
    var revealNodes: [Int: SKSpriteNode] = [:]
    var npcNodes: [Int: SKNode] = [:]
    let coreNode = SKSpriteNode()
    let grandmaNode = SKSpriteNode()
    let jarGlow = SKSpriteNode()
    var shake = 0.0

    var lastTime: TimeInterval = 0
    var keysDown = Set<String>()
    var mouseScene = CGPoint.zero
    var paused_ = true
    var lightDirty = true
    var snowTimer = 0.0
    var snapCamera = false
    /// The disaster's glimpse: the camera sinks to the sky locked in the ninth floor and comes back (seconds into it, 0 = off).
    var glimpseT = 0.0
    static let glimpseLength = 4.2
    /// Paintings in the side passages: names, scratches, cots, the painted sky. Drawn over tiles, under the lighting.
    let decorNode = SKNode()
    /// What the jar's lens shows through the rock; drawn above the darkness.
    let lensNode = SKNode()
    var lensT = 0.0

    func syncLens(_ dt: Double) {
        lensT -= dt
        guard lensT <= 0 else { return }
        lensT = 0.25
        lensNode.removeAllChildren()
        guard game.loaded, !paused_ else { return }
        let (marks, way) = game.lensMarks()
        let pulse = SKAction.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.6), .fadeAlpha(to: 0.95, duration: 0.6)]))
        func color(_ t: Int) -> SKColor {
            switch t {
            case Tile.coal: return SKColor(white: 0.75, alpha: 1)
            case Tile.iron: return SKColor(red: 0.95, green: 0.72, blue: 0.6, alpha: 1)
            case Tile.gold: return SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
            case Tile.diamondOre: return SKColor(red: 0.5, green: 0.95, blue: 1, alpha: 1)
            case Tile.hiddenVein: return SKColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
            case Tile.chest, Tile.throne: return SKColor(red: 1, green: 0.8, blue: 0.35, alpha: 1)
            case Tile.ghostStone: return SKColor(red: 0.75, green: 0.55, blue: 1, alpha: 1)
            case Tile.tideWall: return SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
            case Tile.crack: return SKColor(red: 0.55, green: 1, blue: 0.6, alpha: 1)
            case Tile.junction: return SKColor(red: 0.5, green: 0.85, blue: 1, alpha: 1)
            default: return SKColor(red: 0.95, green: 1, blue: 0.85, alpha: 1)
            }
        }
        for m in marks {
            let c = color(m.kind)
            let p = scenePos(Double(m.x) + 0.5, Double(m.y) + 0.5)
            if game.lens == .ore {
                let g = SKSpriteNode(texture: assets.glow); g.size = CGSize(width: 14, height: 14); g.color = c; g.colorBlendFactor = 1; g.blendMode = .add; g.position = p
                let gem = SKSpriteNode(color: c, size: CGSize(width: 4, height: 4)); gem.zRotation = .pi / 4; g.addChild(gem)
                g.run(pulse); lensNode.addChild(g)
            } else {
                let f = SKSpriteNode(texture: assets.cursor); f.size = CGSize(width: 16, height: 16); f.color = c; f.colorBlendFactor = 1; f.position = p
                f.run(pulse); lensNode.addChild(f)
            }
        }
        if let w = way, let tex = HUD.symbolTexture("arrowtriangle.right.fill") {
            // an arrow beside the player, turned toward the nearest vein down
            let a = atan2(-(Double(w.y) - game.player.y), Double(w.x) + 0.5 - game.player.x)
            let n = SKSpriteNode(texture: tex); n.size = CGSize(width: 12, height: 12); n.color = color(Tile.crack); n.colorBlendFactor = 1
            n.position = scenePos(game.player.x + cos(a) * 2.2, game.player.y + 0.8 - sin(a) * 2.2); n.zRotation = CGFloat(a)
            n.run(pulse); lensNode.addChild(n)
        }
    }

    /// A title card each time the player arrives on a floor: below its ceiling, or on floor 4 after the descent begins.
    func updateStageTitle() {
        guard game.disasterStruck else { lastStageShown = nil; return }
        let py = Int(floor(game.player.y)), f = Layers.index(forY: py)
        let inside = f == 4 || (f >= 5 && py >= Stage.ceiling(f))
        guard inside, f != lastStageShown, let t = Stage.title(f) else { return }
        lastStageShown = f
        hud.showStage(number: t.number, name: t.name, line: t.line, tint: Stage.sky(max(5, f)).aurora)
    }

    func buildPassageDecor() {
        decorNode.removeAllChildren()
        for j in Junction.all {
            for d in j.decor(worldWidth: game.world.w) {
                guard let tex = assets.decor[d.kind] else { continue }
                let n = SKSpriteNode(texture: tex); n.anchorPoint = CGPoint(x: 0, y: 1); n.size = tex.size()
                n.position = scenePos(Double(d.x), Double(d.y)); decorNode.addChild(n)
            }
        }
    }

    /// Turning a corner: the view jumps to the passage under a dark panel that sweeps away sideways, like the wall swinging past.
    func playTurn(toRight: Bool) {
        snapCamera = true; lightDirty = true
        let w = size.width / zoom, h = size.height / zoom
        let curtain = SKSpriteNode(color: .black, size: CGSize(width: w * 1.2, height: h * 1.2)); curtain.zPosition = 30
        let edge = SKSpriteNode(color: SKColor(white: 0.25, alpha: 1), size: CGSize(width: 6 / zoom * 3, height: h * 1.2))
        edge.position = CGPoint(x: (toRight ? -1 : 1) * w * 0.6, y: 0); curtain.addChild(edge)
        cam.addChild(curtain)
        let dir: CGFloat = toRight ? -1 : 1
        curtain.run(.sequence([.wait(forDuration: 0.06), .group([.moveBy(x: dir * w * 1.25, y: 0, duration: 0.38), .fadeAlpha(to: 0.6, duration: 0.38)]), .removeFromParent()]))
        cam.run(.sequence([.scaleX(to: cam.xScale * 0.92, duration: 0.08), .scaleX(to: cam.xScale, duration: 0.3)]))
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1)
        scaleMode = .resizeFill
        camera = cam; addChild(cam)
        chunkRenderer = ChunkRenderer(world: game.world)
        addChild(bgNode)              // bg content is attached to camera below
        addChild(worldNode)
        worldNode.addChild(chunkRenderer.node)
        worldNode.addChild(decorNode)
        lensNode.zPosition = 41
        worldNode.addChild(entityNode)
        worldNode.addChild(fxNode)
        setupBackground()
        setupPlayer()
        setupLighting()
        setupMotes()
        hud = HUD(scene: self)
        cam.addChild(hud.root)
        gradeNode.blendMode = .multiply; gradeNode.zPosition = 500; gradeNode.alpha = 1
        cam.addChild(gradeNode)
        applyZoom()

        game.onTileChanged = { [weak self] x, y in self?.chunkRenderer.invalidate(tileX: x, tileY: y); self?.lightDirty = true }
        let sound = Sound.shared; game.onSFX = { sound.play($0) }   // touching it starts the music
        game.onDigStrike = { [weak self] in guard let self = self else { return }; self.shake = max(self.shake, 0.1); self.digKick = 1 }
        game.onMessage = { [weak self] m in self?.hud.showMessage(m) }
        game.onTip = { [weak self] m in self?.hud.showTip(m) }
        game.onInventoryChanged = { [weak self] in self?.hud.inventoryDirty = true }
        game.onSave = { [weak self] in self?.save() }
        game.onStoryEvent = { [weak self] ev in
            guard let self = self else { return }
            switch ev {
            case "disaster": self.shake = 1.6; self.glimpseT = 0.001
            case "tremor": self.shake = 0.5
            case "collapse": self.shake = 1.2
            case "choice": self.hud.showChoice()
            case "up", "stay": self.chunkRenderer.coreAwake = true; self.chunkRenderer.invalidate(tileX: self.game.world.coreX, tileY: self.game.world.coreY)
            case "sky": self.shake = 0.4
            case "turnLeft", "turnRight": self.playTurn(toRight: ev == "turnRight")
            default: break
            }
        }

        // a deterministic world behind the menu so the title screen is not empty
        game.world.generate(seed: 20261029)
        game.placePlayer()
        hud.showMenu(hasSave: SaveStore.exists())
        view.window?.makeFirstResponder(self)
    }

    func applyZoom() {
        cam.setScale(1 / zoom)
        layoutBackground()
        hud?.layout()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutBackground(); hud?.layout() }

    // MARK: setup

    func setupBackground() {
        skyNode = SKSpriteNode(color: .black, size: CGSize(width: 10, height: 10)); skyNode.zPosition = -100
        let u = skyUniforms
        skyNode.shader = SKShader(source: GameScene.skyShader, uniforms: [u.day, u.dusk, u.under, u.cam, u.res, u.stage, u.stop, u.sbot, u.saur])
        cam.addChild(skyNode)
        starsNode = SKSpriteNode(texture: assets.stars); starsNode.zPosition = -99; starsNode.alpha = 0
        cam.addChild(starsNode)
        moonNode = SKSpriteNode(texture: assets.glow); moonNode.color = SKColor(red: 0.85, green: 0.9, blue: 1, alpha: 1); moonNode.colorBlendFactor = 1; moonNode.zPosition = -98; moonNode.size = CGSize(width: 60, height: 60)
        cam.addChild(moonNode)
        for i in 0..<4 {
            let a = SKSpriteNode(texture: assets.mountains0); a.anchorPoint = CGPoint(x: 0, y: 0); a.zPosition = -97; a.colorBlendFactor = 1
            let b = SKSpriteNode(texture: assets.mountains1); b.anchorPoint = CGPoint(x: 0, y: 0); b.zPosition = -96; b.colorBlendFactor = 1
            cam.addChild(a); cam.addChild(b); mountainsA.append(a); mountainsB.append(b); _ = i
        }
    }

    static let skyShader = """
    void main() {
        vec2 px = floor(v_tex_coord * u_res / 3.0) * 3.0 / u_res;   // 3pt blocks, like the art
        float t = u_time;
        vec3 top = mix(vec3(0.02, 0.03, 0.08), vec3(0.04, 0.14, 0.22), u_day);
        vec3 bot = mix(vec3(0.05, 0.04, 0.12), vec3(0.16, 0.46, 0.50), u_day) + vec3(0.30, 0.06, 0.24) * u_dusk;
        vec3 col = mix(bot, top, px.y);
        float x = px.x * 2.5 + u_cam;
        float a = 0.0;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float edge = 0.55 + fi * 0.1 + sin(x * 1.6 + fi * 2.1 + t * 0.06 * (fi + 1.0)) * 0.07 + sin(x * 4.1 - t * 0.1 + fi) * 0.025;
            float d = px.y - edge;
            float curtain = step(0.0, d) * exp(-d * 7.0);
            float rays = 0.55 + 0.45 * sin(x * 38.0 + fi * 3.0 + t * 0.25);
            a += curtain * rays * (0.55 - fi * 0.14);
        }
        vec3 aur = mix(vec3(0.30, 1.00, 0.78), vec3(0.72, 0.42, 1.00), clamp((px.y - 0.55) * 2.2, 0.0, 1.0));
        col += aur * a * (0.15 + 0.85 * u_day);
        // a stage's own sky: its gradient and its aurora colour, over the same moving curtains
        vec3 scol = mix(u_sbot.rgb, u_stop.rgb, px.y) + u_saur.rgb * a * u_saur.a;
        col = mix(col, scol, u_stage);
        col = floor(col * 20.0) / 20.0;
        col = mix(col, vec3(0.05, 0.05, 0.08), u_under);
        gl_FragColor = vec4(col, 1.0);
    }
    """

    func setupMotes() {
        motes.particleTexture = assets.pixel
        motes.particleBirthRate = 7
        motes.particleLifetime = 9; motes.particleLifetimeRange = 5
        motes.particlePositionRange = CGVector(dx: 900, dy: 520)
        motes.emissionAngle = .pi / 2; motes.emissionAngleRange = 0.7
        motes.particleSpeed = 7; motes.particleSpeedRange = 5
        motes.particleSize = CGSize(width: 2, height: 2)
        motes.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0.5, 0], times: [0, 0.2, 0.7, 1])
        motes.particleColorBlendFactor = 1
        motes.particleColorRedRange = 0.25; motes.particleColorGreenRange = 0.25; motes.particleColorBlueRange = 0.25
        motes.particleBlendMode = .add
        motes.zPosition = 44                 // above the darkness: they are light
        motes.targetNode = fxNode
        fxNode.addChild(motes)
        motes.advanceSimulationTime(10)
    }

    /// Mote color: teal-gold on the surface, the floor's own light below.
    var moteColor: SKColor {
        switch game.currentFloor {
        case 5: return SKColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
        case 6: return SKColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
        case 7: return SKColor(red: 0.45, green: 0.7, blue: 1, alpha: 1)
        case 8: return SKColor(red: 0.75, green: 0.5, blue: 1, alpha: 1)
        case 9: return SKColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)
        default: return SKColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 1)
        }
    }

    /// Background sprites and the HUD are camera children: SpriteKit cancels the camera's scale for them, so they are sized in plain points.
    func layoutBackground() {
        let w = size.width, h = size.height
        skyNode.size = CGSize(width: w + 4, height: h + 4)
        skyUniforms.res.vectorFloat2Value = vector_float2(Float(w + 4), Float(h + 4))
        starsNode.size = CGSize(width: w + 4, height: h + 4)
        for (i, m) in mountainsA.enumerated() { m.size = CGSize(width: 768, height: 240); _ = i }
        for m in mountainsB { m.size = CGSize(width: 768, height: 240) }
    }

    func setupPlayer() {
        playerBody.texture = assets.playerFrames[0][0]; playerBody.size = CGSize(width: 20, height: 32); playerBody.anchorPoint = CGPoint(x: 0.5, y: 0)
        playerNode.addChild(playerBody)
        armNode.texture = assets.armFrames[0]; armNode.size = CGSize(width: 6, height: 12); armNode.anchorPoint = CGPoint(x: 0.5, y: 0.92); armNode.zPosition = 1
        armNode.position = CGPoint(x: 1, y: 15)
        heldNode.size = CGSize(width: 14, height: 14); heldNode.anchorPoint = CGPoint(x: 0.2, y: 0.2); heldNode.position = CGPoint(x: 1, y: -9); heldNode.zRotation = -0.3
        armNode.addChild(heldNode)
        playerNode.addChild(armNode)
        crownNode.texture = assets.itemTexture(Item.crown); crownNode.size = CGSize(width: 14, height: 14); crownNode.position = CGPoint(x: 0, y: 34); crownNode.zPosition = 2; crownNode.isHidden = true
        playerNode.addChild(crownNode)
        playerNode.zPosition = 10
        entityNode.addChild(playerNode)
        cursorNode.texture = assets.cursor; cursorNode.size = CGSize(width: 18, height: 18); cursorNode.zPosition = 50; cursorNode.alpha = 0.9
        fxNode.addChild(cursorNode)
        crackNode.texture = assets.pixel; crackNode.size = CGSize(width: 16, height: 16); crackNode.color = .black; crackNode.colorBlendFactor = 1; crackNode.alpha = 0; crackNode.zPosition = 5
        fxNode.addChild(crackNode)
        placeGhost.size = CGSize(width: 16, height: 16); placeGhost.alpha = 0.45; placeGhost.zPosition = 49
        fxNode.addChild(placeGhost)
        jarGlow.texture = assets.glow; jarGlow.size = CGSize(width: 70, height: 70); jarGlow.colorBlendFactor = 1; jarGlow.blendMode = .add; jarGlow.zPosition = 45; jarGlow.alpha = 0.35
        fxNode.addChild(jarGlow)
        coreNode.texture = assets.coreFrames[0]; coreNode.size = CGSize(width: 48, height: 48); coreNode.anchorPoint = CGPoint(x: 0.5, y: 0); coreNode.zPosition = 6
        entityNode.addChild(coreNode)
        grandmaNode.size = CGSize(width: 20, height: 32); grandmaNode.anchorPoint = CGPoint(x: 0.5, y: 0); grandmaNode.zPosition = 8; grandmaNode.isHidden = true
        entityNode.addChild(grandmaNode)
    }

    func setupLighting() {
        lightSprite.blendMode = .multiply
        lightSprite.anchorPoint = CGPoint(x: 0, y: 0)
        lightSprite.zPosition = 40
        worldNode.addChild(lightSprite)
        worldNode.addChild(lensNode)
    }

    // MARK: game flow

    func startNew() { game.newGame(); afterLoad() }
    func continueGame() {
        if game.loaded { paused_ = false; hud.hideMenu(); return }
        if SaveStore.load(into: game) {
            if let d = SaveStore.lastLoaded { Sound.shared.enabled = d.sound; if d.zoom >= 0 && d.zoom < 3 { zoomIndex = d.zoom } }
            afterLoad()
        } else { startNew() }
    }
    private func afterLoad() {
        chunkRenderer.invalidateAll(); lightDirty = true; paused_ = false
        for (_, n) in enemyNodes { n.removeFromParent() }; enemyNodes.removeAll()
        for (_, n) in dropNodes { n.removeFromParent() }; dropNodes.removeAll()
        for (_, n) in npcNodes { n.removeFromParent() }; npcNodes.removeAll()
        for (_, n) in revealNodes { n.removeFromParent() }; revealNodes.removeAll()
        chunkRenderer.coreAwake = game.act >= 3
        buildPassageDecor()
        hud.hideMenu(); hud.inventoryDirty = true
        cam.position = scenePos(game.player.x, game.player.y)
    }
    func save() { if game.loaded { SaveStore.save(game, zoom: zoomIndex, sound: Sound.shared.enabled) } }
    func openMenu() { save(); paused_ = true; hud.showMenu(hasSave: game.loaded || SaveStore.exists()) }

    // MARK: input

    override var acceptsFirstResponder: Bool { true }

    /// Physical key names, so shortcuts keep working with Korean or any other input source selected.
    private static let keyNames: [UInt16: String] = [
        11: "b", 9: "v", 8: "c", 0: "a", 1: "s", 2: "d", 13: "w", 12: "q", 14: "e", 15: "r", 17: "t", 3: "f", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        48: "tab", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        123: "left", 124: "right", 126: "up", 125: "down", 49: "space", 36: "return", 76: "return",
    ]

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        if event.keyCode == 53 {
            if hud.panelOpen { hud.closePanels() } else if paused_ { if game.loaded { continueGame() } } else { openMenu() }
            return
        }
        guard let c = GameScene.keyNames[event.keyCode] else { return }
        keysDown.insert(c)
        if hud.modalOpen || hud.panelOpen {
            if hud.handleNavKey(c) { return }
        }
        if paused_ { return }
        if let d = Int(c), d >= 1 && d <= Game.handSlots { selectSlot(d - 1) }
        switch c {
        case "t": game.skipTutorial()
        case "e": hud.togglePanel(.craft)
        case "i": hud.togglePanel(.inventory)
        case "j": hud.togglePanel(.jar)
        case "r": hud.togglePanel(.reign)
        case "tab": game.cycleLens()
        case "c": game.toggleCover()
        case "b": game.buildTurret()
        case "v": game.buildWall()
        case "q": game.dropHeld()
        case "m": hud.showMinimapLarge.toggle()
        case "f": game.feedJar(slot: game.player.sel); if hud.panelKind == .jar { hud.openPanel(.jar) }
        case "k":
            game.input.keyboardAim = true
            if !talkToNearbyNPC() { game.input.clicked = true }
        case "l": game.input.keyboardAim = true
        default: break
        }
    }
    override func keyUp(with event: NSEvent) {
        if let c = GameScene.keyNames[event.keyCode] { keysDown.remove(c) }
    }
    /// Camp folk are talked to with K, like everything else in reach.
    private func talkToNearbyNPC() -> Bool {
        let p = game.player
        for (i, n) in npcNodes where abs(n.position.x / TILE_PX - CGFloat(p.x)) < 3 && abs(-n.position.y / TILE_PX - CGFloat(p.y)) < 4 {
            hud.showMessage(npcLine(i)); return true
        }
        return false
    }
    func selectSlot(_ i: Int) {
        game.player.sel = i; hud.inventoryDirty = true
        if let s = game.player.held { hud.showTip(itemName(s.id) + ((ITEMS[s.id]?.use != nil) ? " · K 사용" : "")) }
    }
    override func mouseDown(with event: NSEvent) {
        mouseScene = event.location(in: self)
        game.input.keyboardAim = false
        if hud.handleClick(scenePoint: mouseScene) { return }
        if paused_ { return }
        if let n = nodes(at: mouseScene).first(where: { ($0.name ?? "").hasPrefix("npc:") }), let i = Int(n.name!.dropFirst(4)) { hud.showMessage(npcLine(i)); return }
        game.input.mouseDown = true; game.input.clicked = true
    }
    override func mouseDragged(with event: NSEvent) { mouseScene = event.location(in: self) }
    override func mouseUp(with event: NSEvent) { game.input.mouseDown = false }
    override func rightMouseDown(with event: NSEvent) { mouseScene = event.location(in: self); game.input.keyboardAim = false; if !hud.panelOpen && !paused_ { game.input.rightDown = true } }
    override func rightMouseDragged(with event: NSEvent) { mouseScene = event.location(in: self) }
    override func rightMouseUp(with event: NSEvent) { game.input.rightDown = false }
    override func scrollWheel(with event: NSEvent) {
        if paused_ { return }
        let dy = event.scrollingDeltaY
        if abs(dy) < 0.5 { return }
        selectSlot((game.player.sel + (dy < 0 ? 1 : Game.handSlots - 1)) % Game.handSlots)
    }

    func pollMouse() {
        guard let v = view, let win = v.window else { return }
        let p = win.mouseLocationOutsideOfEventStream
        let inView = v.convert(p, from: nil)
        mouseScene = convertPoint(fromView: inView)
    }

    // MARK: frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, currentTime - lastTime)
        lastTime = currentTime
        pollMouse()
        let wm = (x: Double(mouseScene.x / TILE_PX), y: Double(-mouseScene.y / TILE_PX))
        if !paused_ {
            game.input.left = keysDown.contains("a") || keysDown.contains("left")
            game.input.right = keysDown.contains("d") || keysDown.contains("right")
            game.input.jump = keysDown.contains("space")
            game.input.up = keysDown.contains("w") || keysDown.contains("up")
            game.input.actHeld = keysDown.contains("k"); game.input.placeHeld = keysDown.contains("l")
            game.input.down = keysDown.contains("s") || keysDown.contains("down")
            game.input.mouseX = wm.x; game.input.mouseY = wm.y
            game.input.uiOpen = hud.panelOpen
            game.update(dt)
            updateStageTitle()
            syncLens(dt)
            Sound.shared.mood = game.musicMood
        }
        // camera follows the player
        var target = scenePos(game.player.x + game.player.face * 1.5, game.player.y + game.player.h / 2)
        if glimpseT > 0 {
            glimpseT += dt
            let core = scenePos(Double(game.world.coreX) + 0.5, Double(game.world.coreY) - 3)
            let t = glimpseT, L = GameScene.glimpseLength
            let k = t < 1.3 ? t / 1.3 : (t < L - 1.3 ? 1 : max(0, (L - t) / 1.3))
            let e = CGFloat(k * k * (3 - 2 * k))
            target = CGPoint(x: target.x + (core.x - target.x) * e, y: target.y + (core.y - target.y) * e)
            snapCamera = true
            if t > 1.3 && t - dt <= 1.3, let tt = Stage.title(9) { hud.showStage(number: tt.number, name: tt.name, line: tt.line, tint: Stage.sky(9).aurora) }
            if t >= L { glimpseT = 0 }
        }
        let halfW = size.width / zoom / 2, halfH = size.height / zoom / 2
        game.viewHalfTiles = Int(ceil(halfW / TILE_PX))
        var cx = cam.position.x + (target.x - cam.position.x) * CGFloat(min(1, dt * 6))
        var cy = cam.position.y + (target.y - cam.position.y) * CGFloat(min(1, dt * 6))
        if snapCamera { cx = target.x; cy = target.y; snapCamera = false }
        cx = max(halfW, min(CGFloat(game.world.w) * TILE_PX - halfW, cx))
        cy = min(-halfH, max(-CGFloat(game.world.h) * TILE_PX + halfH, cy))
        if shake > 0 { shake -= dt; cx += CGFloat.random(in: -3...3) * CGFloat(min(1, shake)); cy += CGFloat.random(in: -3...3) * CGFloat(min(1, shake)) }
        cam.position = CGPoint(x: cx, y: cy)

        let vx0 = Int(floor((cx - halfW) / TILE_PX)), vx1 = Int(ceil((cx + halfW) / TILE_PX))
        let vy0 = Int(floor(-(cy + halfH) / TILE_PX)), vy1 = Int(ceil(-(cy - halfH) / TILE_PX))
        chunkRenderer.update(visibleX0: vx0, visibleY0: vy0, visibleX1: vx1, visibleY1: vy1, dt: dt)
        if lightDirty || game.frame % 3 == 0 {
            game.recomputeLight(x0: vx0 - 14, y0: vy0 - 14, x1: vx1 + 14, y1: vy1 + 14)
            uploadLight(x0: vx0 - 1, y0: vy0 - 1, x1: vx1 + 1, y1: vy1 + 1)
            lightDirty = false
        }
        updateBackground(dt)
        updateGrade(dt)
        syncEntities(dt)
        syncParticles()
        if game.frame % 2 == 0 { syncReveals(x0: vx0, y0: vy0, x1: vx1, y1: vy1) }
        syncStoryNodes()
        updateCursor(game.input.keyboardAim ? (game.aimX, game.aimY) : wm)
        hud.update(dt, game: game, zoom: zoom)
        // ambient snow
        if !paused_ && game.world.biomeAt(Int(game.player.x)) == 1 && Int(game.player.y) < game.world.surfaceAt(Int(game.player.x)) + 2 {
            snowTimer += dt
            if snowTimer > 0.04 {
                snowTimer = 0
                game.particles.append(Particle(x: Double(vx0) + Double.random(in: 0..<Double(vx1 - vx0 + 1)), y: Double(vy0) - 1, vx: Double.random(in: -1...0), vy: Double.random(in: 2...4), t: 10, life: 10, color: RGB(r: 255, g: 255, b: 255), snow: true))
            }
        }
    }

    func uploadLight(x0: Int, y0: Int, x1: Int, y1: Int) {
        let cx0 = max(0, x0), cy0 = max(0, y0), cx1 = min(game.world.w - 1, x1), cy1 = min(game.world.h - 1, y1)
        guard cx1 >= cx0, cy1 >= cy0 else { return }
        let w = cx1 - cx0 + 1, h = cy1 - cy0 + 1
        if lightData.count != w * h * 4 { lightData = [UInt8](repeating: 255, count: w * h * 4) }
        let L = game.light, W = game.world.w
        var k = 0
        for y in cy0...cy1 {
            for x in cx0...cx1 {
                let i = y * W + x
                var r = L.r[i], g = L.g[i], b = L.b[i]
                if Int(r) + Int(g) + Int(b) > 6 { game.world.explored[i] = 1 }
                // Only the unexplored stays black: places already seen keep a dim, remembered light.
                if game.world.explored[i] != 0 { r = max(r, 7); g = max(g, 7); b = max(b, 8) }
                lightData[k] = r &* 17; lightData[k + 1] = g &* 17; lightData[k + 2] = b &* 17; lightData[k + 3] = 255
                k += 4
            }
        }
        let tex = SKTexture(data: Data(lightData), size: CGSize(width: w, height: h), flipped: true)
        tex.filteringMode = .linear
        lightSprite.texture = tex
        lightSprite.size = CGSize(width: CGFloat(w) * TILE_PX, height: CGFloat(h) * TILE_PX)
        lightSprite.position = scenePos(Double(cx0), Double(cy1 + 1))
    }

    // MARK: background

    func updateGrade(_ dt: Double) {
        let f = game.currentFloor
        let want: (r: CGFloat, g: CGFloat, b: CGFloat) = [5: (0.86, 1, 0.88), 6: (1, 0.8, 0.76), 7: (0.78, 0.88, 1), 8: (0.84, 0.78, 1), 9: (1, 0.96, 0.86)][f] ?? (1, 1, 1)
        let k = CGFloat(min(1, dt * 1.5))
        grade = (grade.r + (want.r - grade.r) * k, grade.g + (want.g - grade.g) * k, grade.b + (want.b - grade.b) * k)
        gradeNode.color = SKColor(red: grade.r, green: grade.g, blue: grade.b, alpha: 1)
    }

    func updateBackground(_ dt: Double) {
        let dl = CGFloat(game.dayLight)
        // Nael has no sun: the sky is skymist, teal when the heart beats strong, violet as it fades
        let dusk = max(0, 1 - abs(dl - 0.3) * 4)
        skyUniforms.day.floatValue = Float(dl); skyUniforms.dusk.floatValue = Float(dusk)
        skyUniforms.cam.floatValue = Float(cam.position.x / 4000)
        starsNode.alpha = max(0, (0.45 - dl) * 1.6)
        let w = size.width, h = size.height
        let ang = CGFloat(game.worldTime - 0.25) * .pi * 2
        // the pale moon drifts slowly across, a little brighter when the mist dims
        moonNode.position = CGPoint(x: -cos(ang * 0.5) * w * 0.4, y: h * 0.28 + sin(ang * 0.5) * h * 0.08)
        moonNode.alpha = 0.5 + (1 - dl) * 0.5
        let camX = cam.position.x, camY = cam.position.y
        let mw: CGFloat = 768
        let tintA = SKColor(red: 0.25 + dl * 0.35, green: 0.3 + dl * 0.4, blue: 0.45 + dl * 0.45, alpha: 1)
        let tintB = SKColor(red: 0.18 + dl * 0.25, green: 0.26 + dl * 0.35, blue: 0.3 + dl * 0.3, alpha: 1)
        func place(_ nodes: [SKSpriteNode], par: CGFloat, baseY: CGFloat, tint: SKColor) {
            let off = (-camX * par).truncatingRemainder(dividingBy: mw)
            let start = off - mw
            for (i, n) in nodes.enumerated() {
                n.position = CGPoint(x: -w / 2 + start + CGFloat(i) * mw, y: -h / 2 + baseY - camY * par * 0.3)
                n.color = tint
            }
        }
        place(mountainsA, par: 0.12, baseY: h * 0.25 + 10, tint: tintA)
        place(mountainsB, par: 0.25, baseY: h * 0.12, tint: tintB)
        // underground: fade the sky background to cave darkness
        let depth = CGFloat(game.player.y - Double(game.world.surfaceAt(Int(game.player.x))))
        let under = max(0, min(1, (depth - 6) / 14))
        for n in mountainsA + mountainsB { n.alpha = 1 - under }
        // Stages: below a floor's ceiling the sky is that floor's own; the cave darkness fade does not apply.
        let py = Int(floor(game.player.y)), f = Layers.index(forY: py)
        let onStage = f >= 5 && game.disasterStruck
        let target = Stage.sky(max(5, f))
        let k = Float(min(1, dt * 1.6))
        stageSky.top += (SIMD3(target.top.0, target.top.1, target.top.2) - stageSky.top) * k
        stageSky.bot += (SIMD3(target.bottom.0, target.bottom.1, target.bottom.2) - stageSky.bot) * k
        stageSky.aur += (SIMD4(target.aurora.0, target.aurora.1, target.aurora.2, target.aurora.3) - stageSky.aur) * k
        stageSky.blend += ((onStage ? 1 : 0) - stageSky.blend) * k
        stageSky.stars += ((onStage ? target.stars : 0) - stageSky.stars) * k
        let sb = CGFloat(stageSky.blend)
        skyUniforms.stage.floatValue = stageSky.blend
        skyUniforms.stop.vectorFloat4Value = SIMD4(stageSky.top, 1); skyUniforms.sbot.vectorFloat4Value = SIMD4(stageSky.bot, 1)
        skyUniforms.saur.vectorFloat4Value = stageSky.aur
        skyUniforms.under.floatValue = Float(under * (1 - sb))
        starsNode.alpha = starsNode.alpha * (1 - sb) + CGFloat(stageSky.stars) * sb
        moonNode.alpha *= (1 - sb)
        if sb > 0.01 {
            // the far horizon of the floor, sitting on its hall ground, in the floor's colours
            let ground = scenePos(0, Double(Stage.ceiling(max(5, f)) + Stage.hallDepth(max(5, f)))).y - camY
            let hz = SKColor(red: CGFloat(stageSky.bot.x) * 0.6, green: CGFloat(stageSky.bot.y) * 0.6, blue: CGFloat(stageSky.bot.z) * 0.6, alpha: 1)
            for (i, n) in (mountainsA + mountainsB).enumerated() {
                n.alpha = max(n.alpha, 0.7 * sb); n.color = hz
                n.position.y = ground - (i < mountainsA.count ? 30 : 60)
            }
        }
        motes.position = playerNode.position
        motes.particleColor = moteColor
    }

    // MARK: entities

    func syncEntities(_ dt: Double) {
        let p = game.player
        playerNode.position = scenePos(p.x, p.y + p.h)
        let set = p.armorId == Item.ironArmor ? 1 : (p.armorId == Item.goldArmor ? 2 : (p.armorId == Item.diamondArmor ? 3 : 0))
        var pose = 0
        if !p.ground { pose = p.vy < 0 ? 7 : 8 } else if abs(p.vx) > 0.5 { pose = 1 + Int(p.anim) % 6 }
        playerBody.texture = assets.playerFrames[set][pose]
        armNode.texture = assets.armFrames[set]
        crownNode.isHidden = !game.rulesCurrentFloor
        playerNode.xScale = p.face < 0 ? -1 : 1
        playerNode.alpha = p.dead > 0 ? 0 : ((p.iframe > 0 && Int(p.iframe * 20) % 2 == 0) ? 0.35 : 1)
        let swing = p.swing > 0 ? CGFloat(p.swing / 0.3) * 1.9 : 0
        armNode.zRotation = -(0.35 + swing) + (abs(p.vx) > 0.5 && p.ground ? CGFloat(sin(p.anim)) * 0.3 : 0)
        digKick = max(0, digKick - CGFloat(dt) * 8)
        playerBody.position.y = 0; playerBody.position.x = 0
        if let m = game.mineTarget, game.mineProg > 0 {
            // Raised back on the wind-up, snapping onto the block on the strike.
            let dx = (Double(m.x) + 0.5 - p.x) * p.face, up = (p.y + 0.7) - (Double(m.y) + 0.5)
            let aim = CGFloat(atan2(dx, -up))
            let t = CGFloat(game.digPhase.truncatingRemainder(dividingBy: 1))
            let wind = t < 0.25 ? 1 - t / 0.25 : (t - 0.25) / 0.75
            armNode.zRotation = aim + 1.3 * wind - 0.15
            playerBody.position.y = -digKick
            playerBody.position.x = -digKick
        }
        if let h = p.held { heldNode.isHidden = false; heldNode.texture = assets.itemTexture(h.id); heldNode.size = h.id < 100 ? CGSize(width: 10, height: 10) : CGSize(width: 16, height: 16) } else { heldNode.isHidden = true }

        // enemies
        var seen = Set<UUID>()
        for e in game.enemies {
            seen.insert(e.id)
            let n: SKSpriteNode
            if let ex = enemyNodes[e.id] { n = ex } else {
                n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0.5, y: 0); n.zPosition = 9
                let bar = SKSpriteNode(color: SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1), size: CGSize(width: 16, height: 2)); bar.name = "bar"; bar.anchorPoint = CGPoint(x: 0, y: 0.5)
                let barBg = SKSpriteNode(color: .black, size: CGSize(width: 18, height: 4)); barBg.name = "barbg"; barBg.anchorPoint = CGPoint(x: 0, y: 0.5)
                n.addChild(barBg); n.addChild(bar)
                entityNode.addChild(n); enemyNodes[e.id] = n
            }
            n.position = scenePos(e.x, e.y + e.h)
            n.xScale = e.face < 0 ? -1 : 1
            n.alpha = e.hurt > 0 ? 0.55 : 1
            switch e.type {
            case .slime, .cave, .ice:
                let ci = e.type == .slime ? 0 : (e.type == .cave ? 1 : 2)
                n.texture = assets.slimeFrames[ci][e.ground ? 0 : 1]; n.size = CGSize(width: 24, height: 16)
                n.yScale = e.ground ? 1 : 0.9
            case .zombie:
                n.texture = assets.zombieFrames[e.eatT > 0 ? 4 + Int(e.anim * 4) % 2 : Int(e.anim * 8) % 4]; n.size = CGSize(width: 26, height: 28)
            case .bat:
                n.texture = assets.batFrames[Int(e.anim * 14) % 2]; n.size = CGSize(width: 24, height: 14)
            case .king:
                // Breathes on the ground; stretched tall in the air, since the sheet has no leap pose.
                let founder = !e.isChallenger && e.generation == 1
                let frames = (founder ? e.lordFloor.flatMap { assets.lordFrames[$0] } : nil) ?? assets.kingFrames
                n.texture = frames[e.ground ? Int(e.anim * 3) % frames.count : 0]
                n.size = CGSize(width: 72 * e.drawScale * (e.ground ? 1 : 0.92), height: 66 * e.drawScale * (e.ground ? 1 : 1.1))
                if founder { n.colorBlendFactor = 0 } else if let f = e.lordFloor {
                    let c = Reign.tint(f); n.color = SKColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1); n.colorBlendFactor = 0.45
                } else { n.colorBlendFactor = 0 }
            }
            let showBar = e.hp < e.maxhp && !e.boss
            if let bar = n.childNode(withName: "bar") as? SKSpriteNode, let bg = n.childNode(withName: "barbg") as? SKSpriteNode {
                bar.isHidden = !showBar; bg.isHidden = !showBar
                let top = n.size.height + 5
                bg.position = CGPoint(x: -9, y: top); bar.position = CGPoint(x: -8, y: top)
                bar.size.width = 16 * CGFloat(e.hp) / CGFloat(e.maxhp)
                bar.xScale = n.xScale; bg.xScale = n.xScale
            }
        }
        // turrets: lantern turrets, rebuilt when the number changes; the lens glows up before a shot and flashes on it
        let turrets = game.defense?.turrets ?? []
        if turretNodes.count != turrets.count {
            turretNodes.forEach { $0.removeFromParent() }; turretNodes = []
            for t in turrets {
                let n = SKSpriteNode(texture: assets.turretFrames[0]); n.size = CGSize(width: 16, height: 24); n.anchorPoint = CGPoint(x: 0.5, y: 0); n.zPosition = 8
                n.position = scenePos(Double(t.x) + 0.5, Double(t.y) + 1)
                entityNode.addChild(n); turretNodes.append(n)
            }
        }
        for (i, t) in turrets.enumerated() where i < turretNodes.count {
            (turretNodes[i] as? SKSpriteNode)?.texture = assets.turretFrames[t.cooldown > 0.65 ? 2 : (t.cooldown < 0.25 ? 1 : 0)]
        }
        for (id, n) in enemyNodes where !seen.contains(id) { n.removeFromParent(); enemyNodes[id] = nil }

        // drops
        var seenD = Set<UUID>()
        for d in game.drops {
            seenD.insert(d.uid)
            let n: SKSpriteNode
            if let ex = dropNodes[d.uid] { n = ex } else {
                n = SKSpriteNode(texture: assets.itemTexture(d.id)); n.size = CGSize(width: 10, height: 10); n.zPosition = 8
                entityNode.addChild(n); dropNodes[d.uid] = n
            }
            let bob = CGFloat(sin(d.t * 4)) * 1.5
            n.position = CGPoint(x: CGFloat(d.x) * TILE_PX, y: -CGFloat(d.y + d.h / 2) * TILE_PX + bob)
        }
        for (id, n) in dropNodes where !seenD.contains(id) { n.removeFromParent(); dropNodes[id] = nil }

        // arrows
        var seenA = Set<UUID>()
        for a in game.arrows {
            seenA.insert(a.uid)
            let n: SKSpriteNode
            if let ex = arrowNodes[a.uid] { n = ex } else {
                n = SKSpriteNode(texture: assets.itemTexture(Item.arrow)); n.size = CGSize(width: 14, height: 14); n.zPosition = 8
                entityNode.addChild(n); arrowNodes[a.uid] = n
            }
            n.position = scenePos(a.x, a.y)
            n.zRotation = CGFloat(atan2(-a.vy, a.vx)) - .pi / 4
        }
        for (id, n) in arrowNodes where !seenA.contains(id) { n.removeFromParent(); arrowNodes[id] = nil }

        // floating text
        var seenF = Set<UUID>()
        for f in game.floats {
            seenF.insert(f.uid)
            let n: SKLabelNode
            if let ex = floatNodes[f.uid] { n = ex } else {
                n = SKLabelNode(fontNamed: HUD.fontBold); n.fontSize = 7; n.zPosition = 60
                n.text = f.text; n.fontColor = SKColor(red: CGFloat(f.color.r) / 255, green: CGFloat(f.color.g) / 255, blue: CGFloat(f.color.b) / 255, alpha: 1)
                fxNode.addChild(n); floatNodes[f.uid] = n
            }
            n.position = scenePos(f.x, f.y - 0.3); n.alpha = CGFloat(min(1, f.t))
        }
        for (id, n) in floatNodes where !seenF.contains(id) { n.removeFromParent(); floatNodes[id] = nil }
    }

    func syncParticles() {
        let ps = game.particles
        while particleNodes.count < ps.count {
            let n = SKSpriteNode(texture: assets.pixel); n.size = CGSize(width: 3, height: 3); n.colorBlendFactor = 1; n.zPosition = 7
            fxNode.addChild(n); particleNodes.append(n)
        }
        for (i, n) in particleNodes.enumerated() {
            if i < ps.count {
                let p = ps[i]
                n.isHidden = false
                n.position = scenePos(p.x, p.y)
                n.color = SKColor(red: CGFloat(p.color.r) / 255, green: CGFloat(p.color.g) / 255, blue: CGFloat(p.color.b) / 255, alpha: 1)
                n.size = p.snow ? CGSize(width: 2, height: 2) : CGSize(width: 3, height: 3)
                n.alpha = CGFloat(min(1, p.t / max(0.01, p.life) * 2))
            } else { n.isHidden = true }
        }
        if particleNodes.count > 600 { for n in particleNodes[600...] { n.removeFromParent() }; particleNodes.removeLast(particleNodes.count - 600) }
    }

    /// Overlays showing the truth behind light-gated tiles, faded in by the light channel that reveals them.
    func syncReveals(x0: Int, y0: Int, x1: Int, y1: Int) {
        let w = game.world, L = game.light
        var seen = Set<Int>()
        for y in max(0, y0)...min(w.h - 1, y1) {
            for x in max(0, x0)...min(w.w - 1, x1) {
                let t = w.get(x, y)
                guard t == Tile.hiddenVein || t == Tile.ghostStone || t == Tile.tideWall else { continue }
                let i = y * w.w + x
                var a: CGFloat = 0
                switch t {
                case Tile.hiddenVein: a = CGFloat(Int(L.r[i]) - 6) / 4
                case Tile.ghostStone: a = CGFloat(min(Int(L.r[i]), Int(L.b[i])) - 5) / 4
                default: a = CGFloat(Int(L.b[i]) - 6) / 4
                }
                a = max(0, min(1, a))
                if a <= 0.02 { continue }
                seen.insert(i)
                let n: SKSpriteNode
                if let ex = revealNodes[i] { n = ex } else {
                    n = SKSpriteNode(); n.size = CGSize(width: 16, height: 16); n.anchorPoint = CGPoint(x: 0, y: 1); n.zPosition = 3
                    n.position = scenePos(Double(x), Double(y))
                    if t == Tile.hiddenVein {
                        let ore = y >= Layers.darkTop ? Tile.diamondOre : Tile.gold
                        if let img = assets.tile(ore, col: w.autotileMask(x, y, Tile.stone) * 2) { n.texture = SKTexture(cgImage: img); n.texture?.filteringMode = .nearest }
                    } else {
                        if let img = assets.wall(kind: 1, variant: (x * 7 + y * 13) & 3) { n.texture = SKTexture(cgImage: img); n.texture?.filteringMode = .nearest }
                        n.color = t == Tile.ghostStone ? SKColor(red: 0.8, green: 0.6, blue: 1, alpha: 1) : SKColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
                        n.colorBlendFactor = 0.35
                    }
                    fxNode.addChild(n); revealNodes[i] = n
                }
                n.alpha = a
            }
        }
        for (k, n) in revealNodes where !seen.contains(k) { n.removeFromParent(); revealNodes[k] = nil }
    }

    func npcLine(_ i: Int) -> String {
        let lines = [
            ["대장장이: 붉은 빛이 돌을 데우면 그 속의 금이 보인다고 하더군.", "대장장이: 용암 옆에 서려면 붉은 빛을 들어. 그게 전부야."],
            ["원예사: 초록 빛 아래선 덩굴이 벽을 타고 자라. 길이 없으면 길을 키워.", "원예사: 병 속 이끼가 젖어 있어야 해. 물을 찾아."],
            ["우물지기: 7층엔 벽처럼 선 물이 있어. 푸른 빛이면 지나갈 수 있지.", "우물지기: 옛 사람들은 하늘이 땅 밑에서 온다고 했어. 그래서 우리가 여기 있는 거야."],
        ]
        let set = lines[i % 3]
        return set[Int(game.storyT / 7) % set.count]
    }

    /// Camp NPCs appear beside lit pedestals; the core sprite sits in the city.
    func syncStoryNodes() {
        let w = game.world
        for (i, p) in w.pedestals.enumerated() {
            let lit = (w.pedestalState["\(p.x),\(p.y)"] ?? 0) > 0
            if lit && npcNodes[i] == nil {
                let n = SKSpriteNode(texture: assets.playerFrames[0][0]); n.size = CGSize(width: 20, height: 32); n.anchorPoint = CGPoint(x: 0.5, y: 0)
                n.color = [SKColor(red: 0.9, green: 0.5, blue: 0.3, alpha: 1), SKColor(red: 0.5, green: 0.8, blue: 0.4, alpha: 1), SKColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)][i % 3]
                n.colorBlendFactor = 0.45; n.name = "npc:\(i)"; n.zPosition = 8
                n.position = scenePos(Double(p.x) + 1.9, Double(p.y) + 1)
                n.xScale = -1
                let bob = SKAction.repeatForever(SKAction.sequence([SKAction.moveBy(x: 0, y: 1, duration: 0.9), SKAction.moveBy(x: 0, y: -1, duration: 0.9)]))
                n.run(bob)
                entityNode.addChild(n); npcNodes[i] = n
            }
        }
        // Grandmother stands where she handed over the jar: on the quiet afternoon, and again once the sky is back.
        let gx = game.spawnX - 2.5
        grandmaNode.isHidden = !((game.act == 1 && !game.disasterStruck) || game.act == 5) || abs(gx - game.player.x) > 50
        if !grandmaNode.isHidden {
            let near = abs(gx - game.player.x) < 3.5
            grandmaNode.texture = assets.grandmaFrames[near && Int(game.storyT * 1.5) % 3 == 0 ? 3 : Int(game.storyT * 2) % 3]
            grandmaNode.position = scenePos(gx, Double(w.surfaceAt(Int(floor(gx)))))
            grandmaNode.xScale = game.player.x < gx ? -1 : 1
        }
        coreNode.position = scenePos(Double(w.coreX) + 0.5, Double(w.coreY) + 1)
        coreNode.texture = assets.coreFrames[game.act >= 3 ? 1 : 0]
        coreNode.isHidden = abs(Double(w.coreX) - game.player.x) > 60
        if game.act >= 3 { coreNode.alpha = 0.85 + CGFloat(sin(game.storyT * 3)) * 0.15 }
        // the jar's glow around the player
        let l = game.jar.light
        jarGlow.position = CGPoint(x: playerNode.position.x, y: playerNode.position.y + 14)
        jarGlow.color = SKColor(red: CGFloat(l.r) / 15, green: CGFloat(l.g) / 15, blue: CGFloat(l.b) / 15, alpha: 1)
        jarGlow.alpha = CGFloat(0.12 + Double(game.jar.brightness) / 15 * 0.25) * CGFloat(game.jarStrength)
        jarGlow.setScale(1 + CGFloat(sin(game.storyT * 2.2)) * 0.05)
        jarGlow.isHidden = game.player.dead > 0
    }

    func updateCursor(_ wm: (x: Double, y: Double)) {
        let tx = Int(floor(wm.x)), ty = Int(floor(wm.y))
        cursorNode.isHidden = paused_ || hud.panelOpen
        cursorNode.position = CGPoint(x: CGFloat(tx) * TILE_PX + 8, y: -CGFloat(ty) * TILE_PX - 8)
        cursorNode.color = game.reach(tx, ty) ? .white : SKColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
        cursorNode.colorBlendFactor = 1
        if let m = game.mineTarget, game.mineProg > 0 {
            crackNode.alpha = (CGFloat(game.mineProg) * 0.55 + digKick * 0.3)
            crackNode.position = CGPoint(x: CGFloat(m.x) * TILE_PX + 8 + digKick * CGFloat.random(in: -1.5...1.5), y: -CGFloat(m.y) * TILE_PX - 8 + digKick * CGFloat.random(in: -1.5...1.5))
        } else { crackNode.alpha = 0 }
        // K's target has the cursor; L's target differs (the nearest free tile), so show it as a faint copy of the block.
        if game.input.keyboardAim, !cursorNode.isHidden, let s = game.player.held, s.id < 100, TILES[s.id].placeable {
            let a = game.placeAim(), gx = Int(floor(a.x)), gy = Int(floor(a.y))
            placeGhost.isHidden = !(game.reach(gx, gy) && [Tile.air, Tile.water].contains(game.world.get(gx, gy)))
            placeGhost.texture = assets.itemTexture(s.id)
            placeGhost.position = CGPoint(x: CGFloat(gx) * TILE_PX + 8, y: -CGFloat(gy) * TILE_PX - 8)
        } else { placeGhost.isHidden = true }
    }
}
