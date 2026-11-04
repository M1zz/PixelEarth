import Foundation

struct Input {
    var left = false, right = false, jump = false, down = false
    var mouseX: Double = 0, mouseY: Double = 0        // world tile coords
    var mouseDown = false, rightDown = false
    var actHeld = false, placeHeld = false              // K and L
    var up = false                                      // W: look up, climb
    var keyboardAim = true                              // K/L act on the tile the player faces; the mouse switches this off
    var clicked = false                                 // left button pressed this frame
    var uiOpen = false
}

enum SFX: String { case dig, brk, place, jump, hurt, pick, craft, swing, bow, hit, die, roar, heal, open }

/// All simulation state and rules. Rendering lives in GameScene; this type never touches SpriteKit.
final class Game {
    /// What the hands can reach without opening the bag: few on purpose, the jar is the real tool.
    static let handSlots = 4
    /// Half the screen width in tiles, kept by the scene so enemies spawn out of sight at any zoom.
    var viewHalfTiles = 23
    let world = World()
    let light = LightMap()
    let player = Player()
    var enemies: [Enemy] = []
    var drops: [Drop] = []
    var arrows: [Arrow] = []
    var particles: [Particle] = []
    var floats: [FloatText] = []
    var boss: Enemy? = nil
    var worldTime = 0.27, day = 1
    let dayLength = 540.0
    var spawnX = 0.0, spawnY = 0.0
    var frame = 0
    var input = Input()
    var mineTarget: (x: Int, y: Int)? = nil
    var mineProg = 0.0
    var digPhase = 0.0          // strikes so far on this block; the fraction drives the swing
    var digStrikes = 0
    static let digStrikesPerSecond = 10.0
    var saveTimer = 0.0
    var loaded = false

    // --- the jar and the story
    var jar = Jar()
    var jarDim = 1.0            // drops when something dangerous is near
    var jarNearOre = false      // bugs cluster toward ore
    /// C: the jar under a cloth. What hunts by light loses you; you see almost nothing.
    var jarCovered = false, shownCover = false
    /// The jar's light this frame: hurt dims it, the cloth nearly hides it, danger makes it flinch.
    var jarStrength: Double {
        if jarCovered { return 0.15 }
        return jarDim * (0.4 + 0.6 * Double(max(0, player.hp)) / Double(max(1, player.maxhp))) * (jarEmpty ? 0.35 : 1)
    }
    /// Light-led creatures follow the player only while they can see the jar, or when close enough to smell them.
    func seesPlayer(_ e: Enemy, dist: Double) -> Bool { !jarCovered || dist < 3.5 || e.lordFloor != nil || e.attackerCost > 0 }
    var act = 1                 // 1 descent, 2 settle, 3 reclaim, 4 stayed below, 5 sky regained
    var storyT = 0.0
    var disasterStruck = false
    var skyFactor = 1.0, skyTarget = 1.0
    var layersSeen: Set<Int> = []
    var ascent = 0.0            // act 3 progress 0...1
    var pendingChoice = false
    // --- the first afternoon (see Tutorial.swift); saves from before it count as finished
    var shownTorchEaten = false
    var lens = Lens.path
    var lensActive = false
    var flickerT = 12.0, shownFlicker = false
    var warnedLowEnergy = false
    /// Light springs: seconds left of the brighter jar, and when each spring was last drawn from (storyT).
    var springGlowT = 0.0
    var springTaken: [String: Double] = [:]
    static let springGlow = 120.0, springRefill = 180.0
    var passagesSeen: Set<Int> = []
    var tutorialStep = Tutorial.done, tutorialCalm = 0.0, tutorialWalked = 0.0, tutorialLastX = 0.0, tutorialSlimeT = 0.0
    var tutorialSpore: (x: Int, y: Int)? = nil, tutorialCovered = false
    var jarLooked = false, tremorStage = 0
    var freeChest: (x: Int, y: Int)? = nil
    // --- floor thrones (see Reign.swift)
    var reigns = Game.freshReigns()
    var siege: Siege? = nil
    var nextSiegeT = Double.random(in: Reign.siegeInterval)
    var floorLord: Enemy? = nil
    var defense: Defense? = nil
    var aimX = 0.0, aimY = 0.0  // tile centre K and L act on this frame
    var placeRepeatT = 0.0, placeHolding = false   // one block per press; holding repeats like a key
    // --- nudges (see KeyHints.swift); saved games already know the basics
    var newItemId: Int? = nil, newItemT = 0.0, craftOpened = true
    var onStoryEvent: ((String) -> Void)?   // "disaster", "collapse", "camp", "choice", "sky"

    var onTileChanged: ((Int, Int) -> Void)?
    var onSFX: ((SFX) -> Void)?
    var onDigStrike: (() -> Void)?
    var onMessage: ((String) -> Void)?
    var onTip: ((String) -> Void)?
    var onInventoryChanged: (() -> Void)?
    var onSave: (() -> Void)?

    var night: Bool { worldTime < 0.2 || worldTime > 0.8 }
    var sunLight: Double { max(0, min(1, (sin((worldTime - 0.25) * .pi * 2) + 0.45) / 1.1)) }
    /// Daylight after the disaster dimmed the sky.
    var dayLight: Double { sunLight * skyFactor }
    var skyLight: RGB { let d = dayLight; return RGB(r: Int((3 + 9 * d).rounded()), g: Int((3 + 12 * d).rounded()), b: Int((5 + 10 * d).rounded())) }

    init() { world.light = light }

    func sfx(_ s: SFX) { onSFX?(s) }
    func message(_ s: String) { onMessage?(s) }
    func tip(_ s: String) { onTip?(s) }

    // MARK: new / place

    func newGame() {
        world.generate(seed: UInt32.random(in: 1...UInt32.max))
        world.ensureLairs(); world.ensureJunctions()
        reigns = Game.freshReigns(); siege = nil; floorLord = nil; defense = nil; world.throneCol = [:]
        placePlayer()
        player.hp = 100; player.maxhp = 100; player.armor = 0; player.armorId = nil
        player.inv = Array(repeating: nil, count: 40); player.sel = 0
        _ = addItem(Item.potion, 1)
        worldTime = 0.33; day = 1
        enemies = []; drops = []; arrows = []; floats = []; particles = []; boss = nil
        jar = Jar(); jarCovered = false; act = 1; storyT = 0; disasterStruck = false; skyFactor = 1; skyTarget = 1
        layersSeen = []; passagesSeen = []; ascent = 0; pendingChoice = false; world.pedestalState = [:]
        startTutorial()
        loaded = true
        message(L("intro.jar")); message(L("intro.flicker")); shownFlicker = true; flickerT = 12
    }

    func placePlayer() {
        var x = world.campX + 18
        while world.get(x, world.surface[x] - 1) != Tile.air && x < world.w - 5 { x += 1 }
        player.x = Double(x) + 0.5; player.y = Double(world.surface[x]) - 2.2
        spawnX = player.x; spawnY = player.y
    }

    // MARK: inventory

    @discardableResult
    func addItem(_ id: Int, _ nIn: Int) -> Bool {
        var n = nIn
        if countItem(id) == 0 { newItemId = id; newItemT = 8; if id == Game.pickaxe { message(L("pickaxe.got")) } }
        if itemStackable(id) {
            for i in 0..<40 {
                if var s = player.inv[i], s.id == id, s.n < 99 {
                    let a = min(n, 99 - s.n); s.n += a; n -= a; player.inv[i] = s
                    if n <= 0 { onInventoryChanged?(); return true }
                }
            }
        }
        for i in 0..<40 where n > 0 {
            if player.inv[i] == nil {
                let a = itemStackable(id) ? min(n, 99) : 1
                player.inv[i] = ItemStack(id: id, n: a); n -= a
            }
        }
        onInventoryChanged?()
        return n <= 0
    }
    func countItem(_ id: Int) -> Int { player.inv.reduce(0) { $0 + (($1?.id == id) ? ($1?.n ?? 0) : 0) } }
    func removeItem(_ id: Int, _ nIn: Int) {
        var n = nIn
        for i in 0..<40 where n > 0 {
            if var s = player.inv[i], s.id == id {
                let r = min(n, s.n); s.n -= r; n -= r
                player.inv[i] = s.n <= 0 ? nil : s
            }
        }
        onInventoryChanged?()
    }
    func dropItem(_ id: Int, _ n: Int, _ x: Double, _ y: Double, vx: Double? = nil, vy: Double? = nil) {
        drops.append(Drop(id: id, n: n, x: x, y: y, vx: vx ?? Double.random(in: -2...2), vy: vy ?? Double.random(in: -8 ... -5)))
    }
    func dropHeld() {
        guard let s = player.held else { return }
        dropItem(s.id, s.n, player.x, player.y + 0.5, vx: player.face * 5, vy: -3)
        player.inv[player.sel] = nil; onInventoryChanged?()
    }

    /// Returns true if the item was consumed/equipped.
    @discardableResult
    func useItem(slot i: Int) -> Bool {
        guard var s = player.inv[i], s.id >= 100, let it = ITEMS[s.id], let use = it.use else { return false }
        switch use {
        case .heal:
            if player.hp >= player.maxhp { tip("체력이 가득 찼습니다"); return false }
            player.hp = min(player.maxhp, player.hp + 60); sfx(.heal); message("체력 +60")
        case .armor:
            if let old = player.armorId { addItem(old, 1) }
            player.armor = it.armor; player.armorId = s.id; sfx(.craft)
            message("\(it.name) 장착 (피해 -\(Int(it.armor * 100))%)")
        case .life:
            if player.maxhp >= 200 { tip("최대 체력이 한계입니다"); return false }
            player.maxhp += 20; player.hp += 20; sfx(.heal); message(L("shard.used")); gainEnergy(Game.shardGain)
        }
        s.n -= 1
        player.inv[i] = s.n <= 0 ? nil : s
        onInventoryChanged?()
        return true
    }

    func nearBench() -> Bool {
        let px = Int(floor(player.x)), py = Int(floor(player.y))
        for y in (py - 5)...(py + 5) { for x in (px - 7)...(px + 7) where world.get(x, y) == Tile.bench { return true } }
        return false
    }
    func canCraft(_ r: Recipe, bench: Bool) -> Bool {
        (!r.bench || bench) && r.input.allSatisfy { countItem($0.0) >= $0.1 }
    }
    func craft(_ r: Recipe) {
        guard canCraft(r, bench: nearBench()) else { return }
        for (id, n) in r.input { removeItem(id, n) }
        addItem(r.out, r.n); sfx(.craft); message("\(itemName(r.out)) 제작!")
    }

    // MARK: combat helpers

    struct HeldStats { var tier: Int; var power: Double; var dmg: Int; var tool: ToolKind? }
    func heldStats() -> HeldStats {
        if let h = player.held, let it = ITEMS[h.id], it.tool == .bow { return HeldStats(tier: 0, power: 1, dmg: it.dmg + jar.strike / 3, tool: .bow) }
        // Bare hands move only soft ground; with the pickaxe the jar's light decides how hard it bites.
        return HeldStats(tier: hasPickaxe ? jar.digTier : 0, power: jar.digPower * (jarEmpty ? 0.5 : 1), dmg: jar.strike, tool: .pick)
    }

    func damagePlayer(_ nIn: Int, from src: Entity? = nil) {
        if player.iframe > 0 || player.dead > 0 { return }
        let lordFactor = rulesCurrentFloor ? Reign.damageTaken : 1
        let n = max(1, Int((Double(nIn) * (1 - max(player.armor, jar.ward)) * lordFactor).rounded()))
        player.iframe = 0.7; player.hp -= n; sfx(.hurt)
        floats.append(FloatText(x: player.x, y: player.y, t: 1, text: "-\(n)", color: RGB(r: 255, g: 107, b: 107)))
        if let s = src { player.vx = (player.x - s.x >= 0 ? 1 : -1) * 7; player.vy = -6 }
        if player.hp <= 0 { player.hp = 0; player.dead = 3.5; sfx(.die); message("쓰러졌습니다… 잠시 후 부활합니다"); playerDied() }
    }
    func damageEnemy(_ e: Enemy, _ n: Int) {
        e.hp -= n; e.hurt = 0.15; sfx(.hit)
        floats.append(FloatText(x: e.x, y: e.y, t: 1, text: "-\(n)", color: RGB(r: 255, g: 255, b: 255)))
        if e.boss && Double.random(in: 0..<1) < 0.4 {
            let s = Enemy(type: .slime, x: e.x + Double.random(in: -1.5...1.5), y: e.y); s.vy = -8; enemies.append(s)
        }
    }
    @discardableResult
    func hitEnemies(cx: Double, cy: Double, radius: Double, dmg: Int, kx: Double) -> Bool {
        var any = false
        for e in enemies {
            let ex = max(e.x - e.w / 2, min(cx, e.x + e.w / 2)), ey = max(e.y, min(cy, e.y + e.h))
            if hypot(ex - cx, ey - cy) < radius {
                damageEnemy(e, dmg); if !e.boss { e.vx = kx * 9; e.vy = -7 }; any = true
            }
        }
        return any
    }

    func tileTier(_ t: Int) -> Int { (t == Tile.rubble && act >= 3) ? 1 : TILES[t].tier }

    func reach(_ tx: Int, _ ty: Int) -> Bool {
        hypot(Double(tx) + 0.5 - player.x, Double(ty) + 0.5 - (player.y + player.h / 2)) <= 6
    }

    // MARK: actions

    /// Left click: use consumable, shoot, open chest, or melee an enemy under the cursor. Returns true if handled.
    func useAt(_ wx: Double, _ wy: Double) -> Bool {
        if let j = nearbyJunction() { turn(at: j.junction, inside: j.inside); return true }
        // a spring answers K before whatever is in hand
        let sx = Int(floor(wx)), sy = Int(floor(wy))
        if world.get(sx, sy) == Tile.lightSpring && reach(sx, sy) { takeSpringLight(sx, sy); return true }
        if world.get(sx, sy) == Tile.emptyLamp && reach(sx, sy) { deliverLight(sx, sy); return true }
        if world.get(sx, sy) == Tile.chest && reach(sx, sy) { openChest(sx, sy); return true }
        let st = heldStats()
        if let h = player.held, let it = ITEMS[h.id], it.use != nil { useItem(slot: player.sel); return true }
        if st.tool == .bow {
            if countItem(Item.arrow) <= 0 { tip("화살이 없습니다"); return true }
            if player.swing > 0 { return true }
            player.swing = 0.35; removeItem(Item.arrow, 1)
            let a = atan2(wy - (player.y + 0.6), wx - player.x)
            arrows.append(Arrow(x: player.x, y: player.y + 0.6, vx: cos(a) * 26, vy: sin(a) * 26, t: 3, dmg: st.dmg))
            player.face = cos(a) > 0 ? 1 : -1; sfx(.bow); return true
        }
        let tx = Int(floor(wx)), ty = Int(floor(wy))
        if world.get(tx, ty) == Tile.chest && reach(tx, ty) { openChest(tx, ty); return true }
        if world.get(tx, ty) == Tile.core && reach(tx, ty) { touchCore(); return true }
        if world.get(tx, ty) == Tile.throne && reach(tx, ty) { touchThrone(tx, ty); return true }
        if world.get(tx, ty) == Tile.lightSpring && reach(tx, ty) { takeSpringLight(tx, ty); return true }
        if world.get(tx, ty) == Tile.pedestal && reach(tx, ty) { tip(pedestalHint(tx, ty)); return true }
        if world.get(tx, ty) == Tile.door && reach(tx, ty) { return true }
        var near = false
        for e in enemies where abs(e.x - wx) < e.w / 2 + 0.7 && wy > e.y - 0.6 && wy < e.y + e.h + 0.6 && hypot(e.x - player.x, e.y - player.y) < 6.5 { near = true }
        if near && player.swing <= 0 {
            player.swing = 0.3; player.face = wx > player.x ? 1 : -1; sfx(.swing)
            hitEnemies(cx: wx, cy: wy, radius: 1.2, dmg: st.dmg, kx: player.face); return true
        }
        return false
    }

    func openChest(_ tx: Int, _ ty: Int) {
        let key = "\(tx),\(ty)"
        let loot = world.chests[key] ?? [ItemStack(id: Tile.greenSpore, n: 2)]
        world.chests[key] = nil
        setTile(tx, ty, Tile.air); sfx(.open)
        for s in loot { dropItem(s.id, s.n, Double(tx) + 0.5, Double(ty) + 0.3) }
        dropItem(Tile.chest, 1, Double(tx) + 0.5, Double(ty) + 0.3)
        message("보물상자를 열었습니다!")
    }

    /// Any placed light the light-starved would rather reach than the player: fire or living light.
    static func isLure(_ t: Int) -> Bool { t == Tile.torch || t == Tile.lantern || t == Tile.redPlant || t == Tile.greenPlant || t == Tile.bluePlant }
    func toggleCover() {
        guard player.dead <= 0 else { return }
        jarCovered.toggle(); sfx(.pick)
        if jarCovered && !shownCover { shownCover = true; tip(L("cover.first")) }
    }
    func nearestTorch(to e: Enemy, within limit: Double) -> (x: Int, y: Int)? {
        let ex = Int(floor(e.x)), ey = Int(floor(e.y + e.h / 2))
        var best: (x: Int, y: Int)? = nil, bd = min(limit, 12.0)
        for y in (ey - 5)...(ey + 5) { for x in (ex - 12)...(ex + 12) where Game.isLure(world.get(x, y)) {
            let d = hypot(Double(x) + 0.5 - e.x, Double(y) + 0.5 - (e.y + e.h / 2))
            if d < bd { bd = d; best = (x, y) }
        } }
        return best
    }

    func takeSpringLight(_ x: Int, _ y: Int) {
        let key = "\(x),\(y)"
        if let t = springTaken[key], storyT - t < Game.springRefill { tip(String(format: L("spring.wait"), Int(Game.springRefill - (storyT - t)))); return }
        springTaken[key] = storyT; springGlowT = Game.springGlow; gainEnergy(Game.springGain)
        _ = addItem(Tile.torch, 3); sfx(.heal)
        for _ in 0..<24 { particles.append(Particle(x: Double(x) + 0.5, y: Double(y) + 0.5, vx: Double.random(in: -3...3), vy: Double.random(in: -6 ... -1), t: 1, life: 1, color: RGB(r: 230, g: 250, b: 210))) }
        message(L("spring.take"))
    }

    func setTile(_ x: Int, _ y: Int, _ v: Int) { world.set(x, y, v); onTileChanged?(x, y) }

    func tryMine(_ dt: Double, _ wx: Double, _ wy: Double) {
        let tx = Int(floor(wx)), ty = Int(floor(wy)); let st = heldStats()
        if !reach(tx, ty) { mineTarget = nil; return }
        let t = world.get(tx, ty); let td = TILES[t]
        if t == Tile.air || td.liquid || t == Tile.chest || t == Tile.core || t == Tile.pedestal || t == Tile.throne { mineTarget = nil; return }
        if t == Tile.hiddenVein && !world.gateOpen(tx, ty, t) && Double.random(in: 0..<1) < 0.02 { tip("돌 속에서 무언가 반짝인 것 같다…") }
        player.face = wx > player.x ? 1 : -1; player.swing = 0.22
        let same = mineTarget.map { $0.x == tx && $0.y == ty } ?? false
        if tileTier(t) > st.tier {
            if !same { tip(digRefusal(t)) }
            mineTarget = (tx, ty); mineProg = 0; return
        }
        if !same { mineTarget = (tx, ty); mineProg = 0 }
        mineProg += dt * st.power / td.hardness * (rulesCurrentFloor ? Reign.mineBonus : 1)
        digPhase += dt * Game.digStrikesPerSecond
        if Int(digPhase) != digStrikes {
            // One strike: the sound and debris land together, which is what makes digging read as rapid blows.
            digStrikes = Int(digPhase)
            sfx(.dig); spawnChips(tx, ty, td.dust)
            onDigStrike?()
        }
        if mineProg >= 1 { breakTile(tx, ty); mineTarget = nil; mineProg = 0 }
    }

    /// Chips fly back toward the digger.
    private func spawnChips(_ tx: Int, _ ty: Int, _ c: RGB) {
        let back: Double = player.x < Double(tx) + 0.5 ? -1 : 1
        for _ in 0..<3 {
            particles.append(Particle(x: Double(tx) + 0.5 + back * 0.5, y: Double(ty) + Double.random(in: 0.1...0.9),
                                      vx: back * Double.random(in: 2...8) + Double.random(in: -1...1), vy: Double.random(in: -9 ... -3), t: 0.45, life: 0.45, color: c))
        }
    }

    func spawnDust(_ tx: Int, _ ty: Int, _ c: RGB, _ n: Int) {
        for _ in 0..<n {
            particles.append(Particle(x: Double(tx) + Double.random(in: 0..<1), y: Double(ty) + Double.random(in: 0..<1),
                                      vx: Double.random(in: -3...3), vy: Double.random(in: -6 ... -1), t: 0.6, life: 0.6, color: c))
        }
    }

    func breakTile(_ tx: Int, _ ty: Int) {
        let t = world.get(tx, ty); if t == Tile.air { return }
        let td = TILES[t]
        jar.energy -= td.tier >= 1 ? 0.4 : 0.1      // every blow the light gives costs a little of it
        setTile(tx, ty, Tile.air); sfx(.brk)
        var drop = td.drop ?? t
        if t == Tile.hiddenVein { drop = world.gateOpen(tx, ty, t) ? (ty >= Layers.darkTop ? Item.diamond : Tile.gold) : Tile.stone }
        if t == Tile.rubble && Double.random(in: 0..<1) < 0.3 { drop = -1 }
        if drop >= 0 { dropItem(drop, 1, Double(tx) + 0.5, Double(ty) + 0.5) }
        spawnDust(tx, ty, td.dust, 7)
        if t == Tile.pine || t == Tile.trunk {   // a placed wood block is just a block; only living trees fall
            var y = ty - 1, n = 0
            while world.get(tx, y) == t { setTile(tx, y, Tile.air); n += 1; y -= 1 }
            if n > 0 { dropItem(Tile.wood, n, Double(tx) + 0.5, Double(ty) - 0.5) }
            let leaf = t == Tile.pine ? Tile.snowleaf : Tile.leaves
            for yy in (y - 3)...ty { for xx in (tx - 4)...(tx + 4) where world.get(xx, yy) == leaf {
                setTile(xx, yy, Tile.air)
                if Double.random(in: 0..<1) < 0.08 { dropItem(Tile.leaves, 1, Double(xx) + 0.5, Double(yy) + 0.5) }
            } }
        }
        if t == Tile.cactus { var y = ty - 1; while world.get(tx, y) == Tile.cactus { setTile(tx, y, Tile.air); y -= 1 } }
        let above = world.get(tx, ty - 1)
        if TILES[above].falls { sandFall(tx, ty) }
        else if above == Tile.torch || above == Tile.flower || above == Tile.shroom || above == Tile.lantern {
            setTile(tx, ty - 1, Tile.air)
            if above != Tile.flower { dropItem(above, 1, Double(tx) + 0.5, Double(ty) - 0.5) }
        }
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1)] {
            let n = world.get(tx + dx, ty + dy)
            if n == Tile.water || n == Tile.lava { setTile(tx, ty, n); break }
        }
    }

    func sandFall(_ tx: Int, _ ty: Int) {
        var y = ty - 1; var col: [Int] = []
        while TILES[world.get(tx, y)].falls { col.append(world.get(tx, y)); setTile(tx, y, Tile.air); y -= 1 }
        var fy = ty
        while world.get(tx, fy + 1) == Tile.air && fy < world.h - 2 { fy += 1 }
        for (i, t) in col.enumerated() { setTile(tx, fy - i, t) }
    }

    func overlaps(_ e: Entity, _ tx: Int, _ ty: Int) -> Bool {
        e.x + e.w / 2 > Double(tx) && e.x - e.w / 2 < Double(tx + 1) && e.y + e.h > Double(ty) && e.y < Double(ty + 1)
    }

    @discardableResult
    func tryPlace(_ wx: Double, _ wy: Double) -> Bool {
        let tx = Int(floor(wx)), ty = Int(floor(wy))
        if world.get(tx, ty) == Tile.pedestal && reach(tx, ty) { return plantOnPedestal(tx, ty) }
        guard let s = player.held, s.id < 100, TILES[s.id].placeable, reach(tx, ty) else { return false }
        let t = world.get(tx, ty)
        guard t == Tile.air || t == Tile.water || t == Tile.leaves || t == Tile.snowleaf || t == Tile.flower else { return false }
        let id = s.id, td = TILES[id]
        if td.solid {
            if overlaps(player, tx, ty) { return false }
            for e in enemies where overlaps(e, tx, ty) { return false }
        }
        let nb = [world.get(tx - 1, ty), world.get(tx + 1, ty), world.get(tx, ty - 1), world.get(tx, ty + 1)]
        guard nb.contains(where: { $0 != Tile.air && $0 != Tile.water && $0 != Tile.lava }) else { return false }
        setTile(tx, ty, id); removeItem(id, 1)
        player.swing = 0.2; player.face = wx > player.x ? 1 : -1; sfx(.place)
        return true
    }

    func attackButton() {
        if player.swing > 0 { return }
        if let h = player.held, let it = ITEMS[h.id], it.use != nil { useItem(slot: player.sel); return }
        let st = heldStats()
        if st.tool == .bow {
            var tgt: Enemy? = nil; var bd = 14.0
            for e in enemies { let d = hypot(e.x - player.x, e.y - player.y); if d < bd { bd = d; tgt = e } }
            _ = useAt(tgt?.x ?? player.x + player.face * 8, tgt.map { $0.y + $0.h / 2 } ?? player.y + 0.5); return
        }
        player.swing = 0.3; sfx(.swing)
        hitEnemies(cx: player.x + player.face * 1.3, cy: player.y + 0.9, radius: 1.6, dmg: st.dmg, kx: player.face)
    }

    // MARK: main update

    func update(_ dt: Double) {
        frame += 1
        worldTime += dt / dayLength
        newItemT = max(0, newItemT - dt)
        if worldTime >= 1 { worldTime -= 1; day += 1; message("심장이 크게 뛴다. 빛안개가 밝아진다 · \(day)일째") }
        let p = player
        if p.dead > 0 {
            p.dead -= dt
            if p.dead <= 0 {
                p.hp = p.maxhp; p.x = spawnX; p.y = spawnY; p.vx = 0; p.vy = 0; p.breath = 10
                // In a battle you come back beside the throne, so a death costs time and throne health, not the whole floor.
                if let d = defense { let t = Reign.thronePosition(d.floor, worldWidth: world.w); p.x = Double(t.x) + 0.5; p.y = Double(t.y) - 2 }
            }
            updateDefense(dt)
            return
        }
        springGlowT = max(0, springGlowT - dt)
        updateEnergy(dt)
        updateStory(dt)
        updateReigns(dt)
        updateDefense(dt)
        // movement
        p.dropThrough = input.down && !input.actHeld && !input.placeHeld
        let spd = p.inWater ? 5.0 : 9.5, acc = p.ground ? 60.0 : 30.0
        if input.left { p.vx = max(-spd, p.vx - acc * dt); p.face = -1 }
        else if input.right { p.vx = min(spd, p.vx + acc * dt); p.face = 1 }
        else { p.vx *= p.ground ? 0.6 : 0.95 }
        // Water: hold Space or W to swim up. Once the head is out and the feet are still wet, the same hold leaps onto the bank.
        let feetWet = world.get(Int(floor(p.x)), Int(floor(p.y + p.h - 0.1))) == Tile.water
        if p.inWater {
            if input.jump || input.up { p.vy = min(p.vy, -6) }
        } else if input.jump && (p.ground || feetWet) && !p.jumpLock {
            p.vy = -14.8; sfx(.jump); p.jumpLock = true
        }
        if !input.jump { p.jumpLock = false }
        // vines: hold to climb, no gravity while on one
        let px0 = Int(floor(p.x))
        let onVine = world.get(px0, Int(floor(p.y + 0.8))) == Tile.vine || world.get(px0, Int(floor(p.y + 1.5))) == Tile.vine
        if onVine { p.vy = (input.jump || input.up ? -5.5 : (input.down ? 5.5 : 0)) - 36 * dt; p.jumpLock = input.jump }
        moveEntity(p, world, dt)
        if p.landedVy > 22 { damagePlayer(Int((p.landedVy - 22) * 5)) }
        if abs(p.vx) > 0.5 && p.ground { p.anim += dt * 12 }
        if p.y > Double(world.h) { damagePlayer(999) }
        if p.inLava { damagePlayer(25); p.vy = -9 }
        if world.get(Int(floor(p.x)), Int(floor(p.y + 0.3))) == Tile.water {
            p.breath -= dt
            if p.breath < 0 { p.breath = 0; if frame % 40 == 0 { damagePlayer(8) } }
        } else { p.breath = min(10, p.breath + dt * 3) }
        do {
            let cx = Int(floor(p.x)), cy = Int(floor(p.y + 1))
            if world.get(cx - 1, cy) == Tile.cactus || world.get(cx + 1, cy) == Tile.cactus || world.get(cx, cy + 1) == Tile.cactus { damagePlayer(4) }
        }
        if p.swing > 0 { p.swing -= dt }
        if p.iframe > 0 { p.iframe -= dt }
        p.regen += dt
        if p.regen > 3 && p.hp < p.maxhp { p.hp = min(p.maxhp, p.hp + 1); p.regen = 2.4 }
        // the jar lives
        jar.tick(dt, inWater: p.inWater && Int(floor(p.y)) > world.surfaceAt(px0) + 2)
        var threat = false, ore = false
        for e in enemies where hypot(e.x - p.x, e.y - p.y) < 7 { threat = true; break }
        let cxI = Int(floor(p.x)), cyI = Int(floor(p.y))
        outer: for y in (cyI - 5)...(cyI + 5) { for x in (cxI - 6)...(cxI + 6) {
            let t = world.get(x, y)
            if t == Tile.gold || t == Tile.diamondOre || t == Tile.hiddenVein || t == Tile.iron { ore = true; break outer }
        } }
        jarDim += ((threat ? 0.5 : 1.0) - jarDim) * min(1, dt * 3)
        jarNearOre = ore

        // cursor actions
        updateAim()
        if !input.uiOpen {
            let wx = aimX, wy = aimY
            var handled = false
            if input.keyboardAim && input.actHeld && p.swing <= 0 && (heldStats().tool == .bow || nearestEnemy(within: 3.2) != nil) { input.clicked = true }
            if input.clicked { handled = useAt(wx, wy) }
            if (input.mouseDown || input.actHeld) && !handled { tryMine(dt, wx, wy) }
            else if input.rightDown || input.placeHeld {
                // A tap lasts several frames; without this, the aim slides to the next free tile and places twice.
                if placeRepeatT <= 0 {
                    let target = input.keyboardAim ? placeAim() : (x: wx, y: wy)
                    tryPlace(target.x, target.y)
                    placeRepeatT = placeHolding ? 0.15 : 0.4
                }
                placeHolding = true; placeRepeatT -= dt; mineTarget = nil
            }
            else { mineTarget = nil }
            if !(input.rightDown || input.placeHeld) { placeHolding = false; placeRepeatT = 0 }
        } else { mineTarget = nil }
        input.clicked = false

        updateSpawning(dt)
        updateEnemies(dt)
        updateDrops(dt)
        updateArrows(dt)
        for i in stride(from: floats.count - 1, through: 0, by: -1) { floats[i].t -= dt; floats[i].y -= dt * 1.2; if floats[i].t <= 0 { floats.remove(at: i) } }
        for i in stride(from: particles.count - 1, through: 0, by: -1) {
            particles[i].t -= dt
            if !particles[i].snow { particles[i].vy += 20 * dt }
            particles[i].x += particles[i].vx * dt; particles[i].y += particles[i].vy * dt
            if particles[i].t <= 0 { particles.remove(at: i) }
        }
        saveTimer += dt
        if saveTimer > 30 { saveTimer = 0; onSave?() }
    }

    private func updateSpawning(_ dt: Double) {
        let px = Int(floor(player.x)), py = Int(floor(player.y))
        let underground = py > world.surfaceAt(px) + 10
        // The quiet afternoon is safe above ground; only the tutorial's own slime appears there.
        if act == 1 && !disasterStruck && !underground { return }
        // A floor you rule is yours: nothing wanders in except challengers.
        if rulesCurrentFloor { return }
        let cap = boss != nil ? 12 : (night ? 8 : (underground ? 6 : 3))
        guard enemies.count < cap, Double.random(in: 0..<1) < dt * (night ? 0.6 : 0.35) else { return }
        let sx = px + (Bool.random() ? -1 : 1) * (viewHalfTiles + 3 + Int.random(in: 0..<10))
        guard sx > 1 && sx < world.w - 2 else { return }
        var sy = -1
        if underground {
            let yy = py + Int(Double.random(in: -11...11))
            for y in yy..<(yy + 14) where world.get(sx, y) == Tile.air && world.get(sx, y - 1) == Tile.air && world.solid(sx, y + 1) && y > world.surface[sx] + 6 { sy = y - 1; break }
        } else {
            sy = world.surface[sx] - 2
            if world.get(sx, sy) != Tile.air || world.get(sx, sy + 1) != Tile.air { sy = -1 }
        }
        guard sy > 0 else { return }
        let lit = light.r[(sy + 1) * world.w + sx] >= 12
        if night || underground || !lit || Bool.random() {
            let type: EnemyType = underground ? (Double.random(in: 0..<1) < 0.4 ? .bat : .cave) : (night ? .zombie : (world.biome[sx] == 1 ? .ice : .slime))
            let e = Enemy(type: type, x: Double(sx) + 0.5, y: Double(sy))
            if type == .bat { e.y -= 2 }
            enemies.append(e)
        }
    }

    private func updateEnemies(_ dt: Double) {
        let p = player
        for i in stride(from: enemies.count - 1, through: 0, by: -1) {
            let e = enemies[i]
            e.t += dt; e.anim += dt; if e.hurt > 0 { e.hurt -= dt }
            let dx = p.x - e.x, dy = (p.y + p.h / 2) - (e.y + e.h / 2), dist = hypot(dx, dy)
            let sees = seesPlayer(e, dist: dist)
            // Lost in the dark: drift the way it was going, turning now and then.
            if !sees && Double.random(in: 0..<1) < dt * 0.5 { e.face = -e.face }
            let sgn: Double = sees ? (dx >= 0 ? 1 : -1) : (e.face >= 0 ? 1 : -1)
            if dist > 55 && !e.boss && e.attackerCost == 0 { enemies.remove(at: i); continue }
            if e.attackerCost > 0 { marchAttacker(e, dt) } else { switch e.type {
            case .zombie:
                // The light-starved go for the nearest flame before the player, and swallow it.
                e.lureT -= dt
                if e.lureT <= 0 { e.lureT = 0.6; e.lure = nearestTorch(to: e, within: dist) }
                let tx = e.lure.map { Double($0.x) + 0.5 } ?? (sees ? p.x : e.x + sgn * 4)
                let s: Double = tx >= e.x ? 1 : -1
                if let l = e.lure, abs(tx - e.x) < 0.9 {
                    e.vx = 0; e.eatT += dt
                    if e.eatT > 1.5 {
                        e.eatT = 0; e.lure = nil
                        if Game.isLure(world.get(l.x, l.y)) { setTile(l.x, l.y, Tile.air); sfx(.hit); if !shownTorchEaten { shownTorchEaten = true; tip(L("starved.ateTorch")) } }
                    }
                } else { e.eatT = 0; e.vx = s * 3.4 }
                e.face = s
                if e.ground {
                    let ahead = Int(floor(e.x + e.face * 0.6))
                    if world.solid(ahead, Int(floor(e.y + e.h - 0.2))) || world.solid(ahead, Int(floor(e.y + e.h - 1.2))) { e.vy = -11.5 }
                }
            case .bat:
                let sp = 4.5
                e.vx += (sgn * sp - e.vx) * dt * 2
                e.vy += (((sees ? (dy >= 0 ? 1 : -1) * sp : 0) + sin(e.t * 6) * 3) - e.vy) * dt * 2
                e.face = sgn
            case .king:
                if e.lordFloor != nil { lordTactics(e, dt) }
                if e.ground {
                    e.vx *= 0.6
                    if e.t > (e.lordFloor != nil ? lordLeapPeriod(e) : 1.5) { e.t = 0; e.vx = lordDirection(e, playerSign: sgn) * Double.random(in: 6...12); e.vy = -Double.random(in: 14...20); sfx(.roar) }
                }
                if dist > 40 && e.lordFloor == nil { e.x = p.x + (Bool.random() ? -12 : 12); e.y = p.y - 8 }
            default:
                if e.ground {
                    e.vx *= 0.6
                    let period = e.type == .cave ? 1.1 : (e.type == .ice ? 1.3 : 1.7)
                    if e.t > period {
                        e.t = 0
                        e.vx = sgn * (e.type == .cave ? 7.5 : (e.type == .ice ? 6 : 5)) * Double.random(in: 0.6...1.2)
                        e.vy = -(e.type == .cave ? 11.5 : 9.5)
                    }
                }
                e.face = sgn
            } }
            moveEntity(e, world, dt)
            if e.inLava { damageEnemy(e, 20) }
            if e.y > Double(world.h) { enemies.remove(at: i); if e.boss { boss = nil }; continue }
            if !sees { e.x = max(1, min(Double(world.w - 2), e.x)) }
            if abs(e.x - p.x) < (e.w + p.w) / 2 && e.y < p.y + p.h && e.y + e.h > p.y { damagePlayer(e.dmg, from: e) }
            if e.hp <= 0 {
                enemies.remove(at: i)
                let c: RGB = e.type == .bat ? RGB(r: 90, g: 70, b: 110) : (e.type == .zombie ? RGB(r: 150, g: 160, b: 172) : (e.type == .ice ? RGB(r: 174, g: 230, b: 255) : (e.type == .cave ? RGB(r: 179, g: 107, b: 216) : RGB(r: 106, g: 214, b: 106))))
                for _ in 0..<10 { particles.append(Particle(x: e.x, y: e.y + e.h / 2, vx: Double.random(in: -4...4), vy: Double.random(in: -8...0), t: 0.8, life: 0.8, color: c)) }
                if e.lordFloor != nil { boss = nil; lordDefeated(e) }
                else if e.attackerCost > 0 { defense?.points += e.attackerCost * 3 }
                else if e.dropsGel { dropItem(Item.gel, 1 + Int.random(in: 0...1), e.x, e.y) }
                else if Double.random(in: 0..<1) < 0.3 { dropItem(Item.potion, 1, e.x, e.y) }
                if !e.boss && e.attackerCost == 0 && Double.random(in: 0..<1) < 0.15 { dropItem(Item.arrow, 4, e.x, e.y) }
            }
        }
    }

    private func updateDrops(_ dt: Double) {
        let p = player
        for i in stride(from: drops.count - 1, through: 0, by: -1) {
            let d = drops[i]
            d.t += dt; moveEntity(d, world, dt); d.vx *= 0.95
            if d.inLava { drops.remove(at: i); continue }
            let dx = p.x - d.x, dy = (p.y + 0.9) - d.y
            let dist = max(0.01, hypot(dx, dy))
            if dist < 3 && d.t > 0.4 { d.vx += dx / dist * 40 * dt; d.vy += dy / dist * 40 * dt - 18 * dt }
            if dist < 0.9 && d.t > 0.4 {
                if addItem(d.id, d.n) {
                    drops.remove(at: i); sfx(.pick)
                    floats.append(FloatText(x: p.x, y: p.y - 0.3, t: 0.9, text: "+\(d.n) \(itemName(d.id))", color: RGB(r: 255, g: 224, b: 138)))
                    continue
                }
            }
            if d.y > Double(world.h) { drops.remove(at: i) }
        }
    }

    private func updateArrows(_ dt: Double) {
        for i in stride(from: arrows.count - 1, through: 0, by: -1) {
            arrows[i].t -= dt; arrows[i].vy += 12 * dt
            arrows[i].x += arrows[i].vx * dt; arrows[i].y += arrows[i].vy * dt
            let a = arrows[i]
            var gone = a.t <= 0
            if world.solid(Int(floor(a.x)), Int(floor(a.y))) {
                gone = true
                if Bool.random() { dropItem(Item.arrow, 1, a.x - a.vx * dt, a.y - a.vy * dt, vx: 0, vy: 0) }
            }
            for e in enemies where a.x > e.x - e.w / 2 && a.x < e.x + e.w / 2 && a.y > e.y && a.y < e.y + e.h {
                damageEnemy(e, a.dmg); if !e.boss { e.vx = (a.vx >= 0 ? 1 : -1) * 5 }; gone = true; break
            }
            if gone { arrows.remove(at: i) }
        }
    }

    // MARK: lighting

    func recomputeLight(x0: Int, y0: Int, x1: Int, y1: Int) {
        // The jar always lights a little way around the player; a spring's glow lights much further for a while.
        let base = jar.light, lift = springGlowT > 0 ? 6 : 3
        let jl = RGB(r: min(15, base.r + lift), g: min(15, base.g + lift), b: min(15, base.b + lift)), k = jarStrength
        let px = Int(floor(player.x)), py = Int(floor(player.y + 1))
        var extra = [LightSource(x: px, y: py, r: Int(Double(jl.r) * k), g: Int(Double(jl.g) * k), b: Int(Double(jl.b) * k))]
        // the jar glows wide: seed the four neighbours too so the core stays bright when it is held
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1)] { extra.append(LightSource(x: px + dx, y: py + dy, r: max(0, Int(Double(jl.r) * k) - 1), g: max(0, Int(Double(jl.g) * k) - 1), b: max(0, Int(Double(jl.b) * k) - 1))) }
        if let b = boss { extra.append(LightSource(x: Int(floor(b.x)), y: Int(floor(b.y + 1)), r: 4, g: 9, b: 12)) }
        light.compute(world: world, x0: x0, y0: y0, x1: x1, y1: y1, sky: skyLight, extra: extra, stages: Stage.floors.map { (Stage.ceiling($0), Stage.sky($0).light) })
    }
}
