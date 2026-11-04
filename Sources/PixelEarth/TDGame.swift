import Foundation

/// Rules of the top-down game. No SpriteKit here; TDScene draws and reads input.
enum TDKind: Int, Codable { case slime, bat, starved, lord }

final class TDEnemy {
    let kind: TDKind; var x: Double; var y: Double
    var hp: Int, maxhp: Int, dmg: Int, speed: Double
    var floor: Int, lordFloor: Int? = nil
    var t = 0.0, hurt = 0.0, face = 1.0, pleaded = false
    let id = UUID()
    init(_ k: TDKind, x: Double, y: Double, floor f: Int) {
        kind = k; self.x = x; self.y = y; floor = f
        switch k {
        case .slime: maxhp = 30 + f * 6; dmg = 8 + f * 2; speed = 2.4
        case .bat: maxhp = 20 + f * 5; dmg = 7 + f * 2; speed = 3.6
        case .starved: maxhp = 46 + f * 6; dmg = 12 + f * 2; speed = 2.0
        case .lord: maxhp = Reign.baseHP(f); dmg = Reign.baseDamage(f); speed = 2.2; lordFloor = f
        }
        hp = maxhp
    }
    var radius: Double { kind == .lord ? 1.3 : 0.4 }
}

struct TDDrop { var id: Int; var n: Int; var x: Double; var y: Double; var t = 0.0; let uid = UUID() }

struct TDSave: Codable {
    var maps: [TDMap]; var floor: Int; var px: Double; var py: Double
    var hp: Int; var maxhp: Int; var inv: [ItemStack?]; var sel: Int; var jar: Jar
    var step: Int; var disaster: Bool; var lordsBeaten: [Int]; var seen: [Int]
}

final class TDGame {
    var maps: [TDMap] = []
    var floor = 0
    var map: TDMap { maps[floor] }
    // player: position is the centre of the feet
    var px = 45.5, py = 34.5, fx = 0.0, fy = 1.0, face = 1.0
    var hp = 100, maxhp = 100, iframe = 0.0, swing = 0.0, dead = 0.0, anim = 0.0, moving = false
    var inv: [ItemStack?] = Array(repeating: nil, count: 24), sel = 0
    var jar = Jar()
    var covered = false, lensActive = false, lens = Lens.path
    var enemies: [TDEnemy] = [], drops: [TDDrop] = [], floats: [FloatText] = [], particles: [Particle] = []
    var mineTarget: TDPoint? = nil, mineProg = 0.0
    var step = 0, disaster = false, calm = 0.0, flickerT = 12.0, time = 0.0
    var lordsBeaten: Set<Int> = [], seen: Set<Int> = [0]
    var springTaken: [String: Double] = [:], springGlowT = 0.0, warnedLow = false
    var input = (left: false, right: false, up: false, down: false, act: false, attack: false)
    // combat: attack cooldown, the slash being drawn, the dodge, and the creature the HUD follows
    var attackCD = 0.0, slashT = 0.0, slashX = 0.0, slashY = 1.0, dodgeT = 0.0, dodgeCD = 0.0, dodgeX = 0.0, dodgeY = 0.0
    var focus: TDEnemy? = nil, hurtFlash = 0.0, hitStop = 0.0, shake = 0.0
    static let attackCooldown = 0.35, dodgeCooldown = 0.9, dodgeTime = 0.18
    var loaded = false

    // callbacks for the scene
    var onMessage: ((String) -> Void)?, onTip: ((String) -> Void)?, onTile: (() -> Void)?, onFloor: ((Int) -> Void)?, onSFX: ((SFX) -> Void)?

    static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PixelEarth")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("topdown1.save")
    }()

    // MARK: lifecycle

    func newGame(seed: UInt32 = UInt32.random(in: 1...UInt32.max)) {
        maps = TD.generate(seed: seed); floor = 0
        px = Double(map.up.x) + 0.5; py = Double(map.up.y) + 0.5
        hp = 100; maxhp = 100; inv = Array(repeating: nil, count: 24); sel = 0; jar = Jar()
        _ = addItem(Item.potion, 1)
        step = 0; disaster = false; calm = 0; flickerT = 12; time = 0; covered = false; lensActive = false
        lordsBeaten = []; seen = [0]; enemies = []; drops = []
        loaded = true
        message(L("intro.jar")); message(L("intro.flicker"))
        onFloor?(0)
    }

    func save() {
        guard loaded else { return }
        let s = TDSave(maps: maps, floor: floor, px: px, py: py, hp: hp, maxhp: maxhp, inv: inv, sel: sel, jar: jar, step: step, disaster: disaster, lordsBeaten: Array(lordsBeaten), seen: Array(seen))
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: TDGame.saveURL, options: .atomic) }
    }
    static var hasSave: Bool { FileManager.default.fileExists(atPath: saveURL.path) }
    func load() -> Bool {
        guard let d = try? Data(contentsOf: TDGame.saveURL), let s = try? JSONDecoder().decode(TDSave.self, from: d) else { return false }
        maps = s.maps; floor = s.floor; px = s.px; py = s.py; hp = s.hp; maxhp = s.maxhp; inv = s.inv; sel = s.sel; jar = s.jar
        step = s.step; disaster = s.disaster; lordsBeaten = Set(s.lordsBeaten); seen = Set(s.seen)
        enemies = []; drops = []; loaded = true
        if let v = maps.first { TD.migrateHouses(v) }
        for m in maps { TD.buildCamp(m); TD.dress(m) }
        populate(); onFloor?(floor)
        return true
    }

    // MARK: messages and items

    func message(_ s: String) { onMessage?(s) }
    func tip(_ s: String) { onTip?(s) }
    func sfx(_ s: SFX) { onSFX?(s) }
    func count(_ id: Int) -> Int { inv.compactMap { $0 }.filter { $0.id == id }.reduce(0) { $0 + $1.n } }
    var hasPickaxe: Bool { count(Item.woodPick) > 0 }
    var held: ItemStack? { inv[sel] }

    @discardableResult func addItem(_ id: Int, _ n: Int) -> Bool {
        var n = n
        if id == Item.woodPick && count(id) == 0 { message(L("pickaxe.got")) }
        if itemStackable(id) { for i in inv.indices where n > 0 { if var s = inv[i], s.id == id, s.n < 99 { let a = min(n, 99 - s.n); s.n += a; n -= a; inv[i] = s } } }
        for i in inv.indices where n > 0 && inv[i] == nil { let a = itemStackable(id) ? min(n, 99) : 1; inv[i] = ItemStack(id: id, n: a); n -= a }
        return n == 0
    }
    func remove(_ id: Int, _ n: Int) {
        var n = n
        for i in inv.indices where n > 0 { if var s = inv[i], s.id == id { let a = min(n, s.n); s.n -= a; n -= a; inv[i] = s.n > 0 ? s : nil } }
    }

    // MARK: per frame

    func update(_ dt: Double) {
        guard loaded else { return }
        time += dt; anim += dt
        if dead > 0 { dead -= dt; if dead <= 0 { revive() }; return }
        shake = max(0, shake - dt)
        if hitStop > 0 { hitStop -= dt; return }          // a blink of stillness when a blow lands
        noticeClues()
        updateGates()
        updateCamp(dt)
        iframe = max(0, iframe - dt); swing = max(0, swing - dt); springGlowT = max(0, springGlowT - dt)
        attackCD = max(0, attackCD - dt); slashT = max(0, slashT - dt); dodgeCD = max(0, dodgeCD - dt); hurtFlash = max(0, hurtFlash - dt)
        if input.attack && attackCD <= 0 { attack() }
        if dodgeT > 0 {
            dodgeT -= dt
            let sp = 15 * dt; tryMove(dx: dodgeX * sp, dy: 0); tryMove(dx: 0, dy: dodgeY * sp)
        } else { movePlayer(dt) }
        if let f = focus, !enemies.contains(where: { $0 === f }) || hypot(f.x - px, f.y - py) > 14 { focus = nil }
        if input.act { act(dt) } else { mineTarget = nil; mineProg = 0 }
        updateEnergy(dt)
        updateEnemies(dt)
        updateDrops(dt)
        updateErrand(dt)
        for i in floats.indices { floats[i].t -= dt; floats[i].y -= dt * 0.8 }
        floats.removeAll { $0.t <= 0 }
        for i in particles.indices { particles[i].t -= dt; particles[i].x += particles[i].vx * dt; particles[i].y += particles[i].vy * dt; particles[i].vy += 9 * dt }
        particles.removeAll { $0.t <= 0 }
    }

    private func movePlayer(_ dt: Double) {
        var vx = 0.0, vy = 0.0
        if input.left { vx -= 1 }; if input.right { vx += 1 }; if input.up { vy -= 1 }; if input.down { vy += 1 }
        moving = vx != 0 || vy != 0
        if moving {
            let l = hypot(vx, vy); vx /= l; vy /= l
            fx = vx; fy = vy; if vx != 0 { face = vx > 0 ? 1 : -1 }
        }
        let sp = 5.5 * dt
        tryMove(dx: vx * sp, dy: 0); tryMove(dx: 0, dy: vy * sp)
        // stairs: stepping onto them takes you to the next floor
        let t = map.get(Int(Foundation.floor(px)), Int(Foundation.floor(py)))
        if t == Tile.stairsDown { changeFloor(+1) } else if t == Tile.stairsUp && self.floor > 0 && stairCooldown <= 0 { changeFloor(-1) }
        stairCooldown = max(0, stairCooldown - dt)
        let ex = Int(Foundation.floor(px)), ey = Int(Foundation.floor(py))
        for y in (ey - 1)...(ey + 1) { for x in (ex - 1)...(ex + 1) where map.inside(x, y) { map.explored[y * map.w + x] = 1 } }
    }
    var stairCooldown = 0.0

    /// The feet are a 0.6 x 0.4 box; walls stop each axis separately so the player slides along them.
    private func tryMove(dx: Double, dy: Double) {
        let nx = px + dx, ny = py + dy
        let x0 = Int(Foundation.floor(nx - 0.3)), x1 = Int(Foundation.floor(nx + 0.3)), y0 = Int(Foundation.floor(ny - 0.2)), y1 = Int(Foundation.floor(ny + 0.2))
        for y in y0...y1 { for x in x0...x1 where map.blocks(x, y) { return } }
        px = nx; py = ny
    }

    func changeFloor(_ d: Int) {
        let nf = floor + d
        guard nf >= 0 && nf < maps.count else { return }
        floor = nf
        let p = d > 0 ? map.up : (map.down ?? map.up)
        // arrive beside the stairs, not on them
        let spots = [(0, 1), (1, 0), (-1, 0), (0, -1), (1, 1), (-1, 1)].map { TDPoint(x: p.x + $0.0, y: p.y + $0.1) }.filter { !map.blocks($0.x, $0.y) && map.get($0.x, $0.y) != Tile.stairsDown && map.get($0.x, $0.y) != Tile.stairsUp }
        let s = spots.first ?? p
        px = Double(s.x) + 0.5; py = Double(s.y) + 0.5; stairCooldown = 0.8
        drops = []; mineTarget = nil
        populate()
        if !seen.contains(floor) { seen.insert(floor); if let frag = Game.fragments[floor] { message(frag) }; if Reign.floors.contains(floor) { message(L("lord.\(floor).rumor")) } }
        sfx(.open); onFloor?(floor)
    }

    /// Creatures of the floor: placed fresh on every arrival, the lord only while unbeaten.
    func populate() {
        enemies = []
        guard floor > 0 else { return }
        var rng = LCG(state: UInt32(floor * 7919) &+ UInt32(time * 10))
        let fire = campFire
        let cells = map.openTiles.filter { c in abs(c.x - map.up.x) + abs(c.y - map.up.y) > 10 && (fire.map { f in abs(c.x - f.x) + abs(c.y - f.y) > 12 } ?? true) }
        for _ in 0..<(3 + floor) where !cells.isEmpty {
            let c = cells[rng.int(cells.count)]
            let k: TDKind = floor >= 7 ? (rng.next() < 0.5 ? .bat : .starved) : (floor >= 3 ? (rng.next() < 0.4 ? .bat : .slime) : .slime)
            enemies.append(TDEnemy(k, x: Double(c.x) + 0.5, y: Double(c.y) + 0.5, floor: floor))
        }
        if Reign.floors.contains(floor) && !lordsBeaten.contains(floor), let t = throne {
            enemies.append(TDEnemy(.lord, x: Double(t.x) + 0.5, y: Double(t.y) + 2.5, floor: floor))
        }
    }
    var throne: TDPoint? { for y in 0..<map.h { for x in 0..<map.w where map.get(x, y) == Tile.throne { return TDPoint(x: x, y: y) } }; return nil }

    // MARK: acting (K)

    /// The lord's charge comes every four seconds; the last second before it is the warning.
    func windingUp(_ e: TDEnemy) -> Bool { e.kind == .lord && Int(e.t * 10) % 40 >= 30 && hypot(px - e.x, py - e.y) < 12 }

    /// The tile the player faces: one step from the feet in the facing direction.
    var target: TDPoint {
        let ax = abs(fx) >= abs(fy) ? (fx > 0 ? 1 : -1) : 0, ay = abs(fx) >= abs(fy) ? 0 : (fy > 0 ? 1 : -1)
        return TDPoint(x: Int(Foundation.floor(px)) + ax, y: Int(Foundation.floor(py)) + ay)
    }

    private func act(_ dt: Double) {
        let t = target, tile = map.get(t.x, t.y)
        if let p = map.props.first(where: { $0.kind.hasPrefix("altar") && $0.x == t.x && $0.y == t.y }) {
            guard mineTarget != t else { return }
            mineTarget = t; useAltar(String(p.kind.dropFirst(5))); return
        }
        if let p = map.props.first(where: { $0.kind.hasPrefix("truth") && $0.x == t.x && $0.y == t.y }) {
            guard mineTarget != t else { return }
            mineTarget = t; readTruth(p); return
        }
        if [Tile.chest, Tile.emptyLamp, Tile.lightSpring, Tile.throne, Tile.core].contains(tile) {
            guard mineTarget != t else { return }       // one use per press
            mineTarget = t
            use(tile, t); return
        }
        mine(t, tile, dt)
    }

    private func use(_ tile: Int, _ t: TDPoint) {
        switch tile {
        case Tile.chest:
            let loot = map.chests["\(t.x),\(t.y)"] ?? [ItemStack(id: Tile.greenSpore, n: 1)]
            map.chests["\(t.x),\(t.y)"] = nil; map.set(t.x, t.y, Tile.air); onTile?(); sfx(.open)
            burst(Double(t.x) + 0.5, Double(t.y) + 0.3, RGB(r: 255, g: 230, b: 150), 12)
            if let k = map.notes?["\(t.x),\(t.y)"] { message(L(k)); map.notes?["\(t.x),\(t.y)"] = nil }
            for s in loot { drops.append(TDDrop(id: s.id, n: s.n, x: Double(t.x) + 0.5, y: Double(t.y) + 0.5)) }
        case Tile.emptyLamp:
            guard spend(Game.houseCost) else { return }
            map.set(t.x, t.y, Tile.lantern); onTile?(); sfx(.heal)
            burst(Double(t.x) + 0.5, Double(t.y) + 0.2, RGB(r: 255, g: 220, b: 120), 18)
            let i = map.houses.firstIndex(of: t) ?? 0
            message(L("house.\(i).lit"))
        case Tile.lightSpring:
            let key = "\(floor):\(t.x),\(t.y)"
            if let w = springTaken[key], time - w < Game.springRefill { tip(String(format: L("spring.wait"), Int(Game.springRefill - (time - w)))); return }
            burst(Double(t.x) + 0.5, Double(t.y) + 0.3, RGB(r: 220, g: 255, b: 200), 14)
            springTaken[key] = time; springGlowT = Game.springGlow; gain(Game.springGain); addItem(Tile.torch, 3); sfx(.heal)
            message(L("spring.take"))
        case Tile.throne:
            tip(lordsBeaten.contains(floor) ? (maps[floor].has("truthKnown") ? L("lord.\(floor).truth") : String(format: L("td.truthPartial"), L("lord.\(floor).name"), truthsFound(floor))) : String(format: L("reign.occupied"), L("lord.\(floor).name")))
        case Tile.core:
            if jar.isWhite { message(L("td.coreWhite")) } else { tip(L("td.coreNeedsWhite")) }
        default: break
        }
    }

    private func mine(_ t: TDPoint, _ tile: Int, _ dt: Double) {
        guard tile != Tile.air, tile != Tile.stairsDown, tile != Tile.stairsUp, tile != Tile.water, tile != Tile.lava else { mineTarget = nil; return }
        let d = TILES[tile]
        let tier = hasPickaxe ? jar.digTier : 0
        if mineTarget != t {
            mineTarget = t; mineProg = 0
            if map.props.contains(where: { $0.kind == "hollow" && $0.x == t.x && $0.y == t.y }) { tip(L("td.clue.hollow")); sfx(.hit) }
        }
        if d.tier > tier || d.hardness >= 1e8 {
            if mineProg == 0 { tip(refusal(tile)) }
            mineProg = 0.0001; return
        }
        mineProg += dt * jar.digPower * (jar.energy < 0.5 ? 0.5 : 1) / max(0.2, d.hardness)
        swing = 0.2
        if Int(time * 10) != Int((time - dt) * 10) { sfx(.dig) }
        if mineProg >= 1 {
            map.set(t.x, t.y, Tile.air); jar.energy -= d.tier >= 1 ? 0.4 : 0.1; sfx(.brk); shake = max(shake, 0.07)
            // the block breaks into bits of itself
            let c = d.dust
            for _ in 0..<9 { particles.append(Particle(x: Double(t.x) + 0.5, y: Double(t.y) + 0.5, vx: Double.random(in: -3.5...3.5), vy: Double.random(in: -6 ... -2), t: 0.5, life: 0.5, color: c)) }
            let drop = d.drop ?? tile
            if drop >= 0 && tile != Tile.flower { drops.append(TDDrop(id: tile == Tile.trunk ? Tile.wood : drop, n: 1, x: Double(t.x) + 0.5, y: Double(t.y) + 0.5)) }
            // grandmother's box was under this mound
            if let b = map.buried, b == t { map.set(t.x, t.y, Tile.chest); map.buried = nil; message(L("td.boxFound")) }
            mineTarget = nil; mineProg = 0; onTile?()
        }
    }

    func refusal(_ t: Int) -> String {
        if t == Tile.hardRock || t == Tile.bedrock || t == Tile.stratum || t == Tile.crystal || t == Tile.ghostStone { return L("dig.hard") }
        if !hasPickaxe { return L("dig.needPick") }
        return L("dig.needLight")
    }

    // MARK: torches and clues

    /// E: set a torch at your feet. A torch from the bag if you have one, else a little of the jar's light.
    /// What you light stays lit: the torches you leave are your map.
    static let torchCost = 6.0
    func placeTorch() {
        let x = Int(Foundation.floor(px)), y = Int(Foundation.floor(py))
        guard floor > 0 || disaster, map.get(x, y) == Tile.air else { tip(L("td.torch.cant")); return }
        if count(Tile.torch) > 0 { remove(Tile.torch, 1) }
        else { guard spend(TDGame.torchCost) else { return } }
        map.set(x, y, Tile.torch); onTile?(); sfx(.place)
        burst(Double(x) + 0.5, Double(y) + 0.3, RGB(r: 255, g: 200, b: 110), 8)
        if !maps[0].has("torchTold") { maps[0].mark("torchTold"); tip(L("td.torch.first")) }
    }

    /// Clues speak once, when you come near: the old torches the first time one is seen, the sound behind rock, the dropped tool.
    private func noticeClues() {
        guard floor > 0 else { return }
        for p in map.props {
            let dd = hypot(Double(p.x) + 0.5 - px, Double(p.y) + 0.5 - py)
            switch p.kind {
            case "oldTorch" where dd < 7 && !maps[0].has("oldTorchSeen"):
                maps[0].mark("oldTorchSeen"); message(L("td.oldTorch.first"))
            case let k where k.hasPrefix("graffiti") && dd < 2.2:
                let key = "clue:\(p.x),\(p.y)"
                if !map.has(key), let lord = Int(k.dropFirst(8)) { map.mark(key); message(String(format: L("td.graffiti"), L("lord.\(lord).rumor"))) }
            case "clueSound" where dd < 5:
                let key = "clue:\(p.x),\(p.y)"; if !map.has(key) { map.mark(key); tip(L("td.clue.sound")) }
            case let k where k.hasPrefix("clueTool") && dd < 2:
                let key = "clue:\(p.x),\(p.y)"; if !map.has(key) { map.mark(key); tip(L("td.clue.tool")) }
            default: break
            }
        }
    }

    // MARK: colour gates

    func jarHas(_ k: String) -> Bool {
        switch k { case "G": return jar.sporeG; case "R": return jar.sporeR; case "B": return jar.sporeB; default: return covered }
    }

    /// A gate gives way when the jar's light of its colour comes near (the dark one, when the jar is covered).
    /// No banner: the first of each kind says one line, the rest just open.
    private func updateGates() {
        guard floor > 0 else { return }
        for p in map.props where p.kind.hasPrefix("gate") {
            let k = String(p.kind.dropFirst(4))
            guard jarHas(k), hypot(Double(p.x) + 0.5 - px, Double(p.y) + 0.5 - py) < 3.2 else { continue }
            map.props.removeAll { $0.x == p.x && $0.y == p.y && $0.kind == p.kind }
            map.set(p.x, p.y, k == "R" ? Tile.dirt : Tile.air)      // red only cracks the rock; the rest opens
            let c: RGB = ["G": RGB(r: 140, g: 255, b: 120), "R": RGB(r: 255, g: 120, b: 80), "B": RGB(r: 120, g: 190, b: 255)][k] ?? RGB(r: 180, g: 150, b: 230)
            burst(Double(p.x) + 0.5, Double(p.y) + 0.5, c, 20); shake = max(shake, 0.1); sfx(.open); onTile?()
            if !maps[0].has("gate:\(k)") { maps[0].mark("gate:\(k)"); message(L("td.gate.\(k)")) }
        }
    }

    // MARK: the camp

    var campFire: TDPoint? { floor == 5 ? map.props.first(where: { $0.kind == "campfire" }).map { TDPoint(x: $0.x, y: $0.y) } : nil }
    var inCamp: Bool { guard let c = campFire else { return false }; return hypot(Double(c.x) + 0.5 - px, Double(c.y) + 0.5 - py) < 6.5 }
    func altarLit(_ k: String) -> Bool { maps.count > 5 && maps[5].has("altar:\(k)") }

    private func updateCamp(_ dt: Double) {
        guard inCamp else { return }
        if !maps[5].has("campSeen") { maps[5].mark("campSeen"); message(L("td.camp.arrive")); save() }
        hpRegen += dt * 4; if hpRegen >= 1 { let n = Int(hpRegen); hpRegen -= Double(n); hp = min(maxhp, hp + n) }
        if altarLit("G") { jar.energy += Game.campFill * dt }
    }
    var hpRegen = 0.0

    private func useAltar(_ k: String) {
        if altarLit(k) { tip(L("td.altar.\(k).lit")); return }
        guard jarHas(k) else { tip(L("td.altar.\(k).need")); return }
        guard spend(15) else { return }
        maps[5].mark("altar:\(k)")
        if k == "B" { maxhp += 20; hp += 20 }
        sfx(.craft); burst(px + fx, py + fy - 0.5, RGB(r: 255, g: 240, b: 180), 20); onTile?()
        message(L("td.altar.\(k).lit"))
        if ["R", "G", "B"].allSatisfy({ altarLit($0) }) { message(L("td.camp.whole")) }
    }

    /// The music follows the place: the afternoon, lost floors, the camp, the deep, and a lord's fight.
    var musicMood: MusicMood {
        if let f = focus, f.kind == .lord { return .fight }
        if floor == 0 { return disaster ? .lost : .afternoon }
        if inCamp { return .camp }
        return floor <= 4 ? .lost : .deep
    }

    // MARK: rumors and truths

    /// How many of a lord's three truths you have found, kept on that floor's map.
    func truthsFound(_ f: Int) -> Int { maps.indices.contains(f) ? (0..<3).filter { maps[f].has("truth:\($0)") }.count : 0 }

    private func readTruth(_ p: TDProp) {
        guard let i = Int(p.kind.dropFirst(5)) else { return }
        let first = !map.has("truth:\(i)")
        map.mark("truth:\(i)")
        message(L("td.truth.\(floor).\(i)"))
        guard first else { return }
        sfx(.heal); burst(Double(p.x) + 0.5, Double(p.y) + 0.3, RGB(r: 240, g: 240, b: 255), 14); onTile?()
        let n = truthsFound(floor)
        message(n == 3 ? String(format: L("td.truthAll"), L("lord.\(floor).name")) : String(format: L("td.truthCount"), L("lord.\(floor).name"), n))
    }

    /// A lord meets you: their creed the first time; and if you know their whole story, the fight can end in words.
    private func lordNotices(_ e: TDEnemy, _ d: Double) {
        guard let f = e.lordFloor, d < 9, !map.has("creed") else { return }
        map.mark("creed")
        message(L("lord.\(f).creed"))
        let n = truthsFound(f)
        if n > 0 && n < 3 { tip(String(format: L("td.truthCount"), L("lord.\(f).name"), n)) }
    }

    /// Called at the lord's plea: with all three truths the child says what they found, and the lord lowers their hands.
    private func lordYields(_ e: TDEnemy) -> Bool {
        guard let f = e.lordFloor, truthsFound(f) == 3 else { return false }
        message(L("td.call.\(f)")); message(String(format: L("td.yield"), L("lord.\(f).name")))
        settleLord(e, yielded: true)
        return true
    }

    private func settleLord(_ e: TDEnemy, yielded: Bool) {
        guard let f = e.lordFloor else { return }
        enemies.removeAll { $0 === e }; focus = nil
        lordsBeaten.insert(f)
        message(L("lord.\(f).last"))
        if truthsFound(f) == 3 { message(L("lord.\(f).truth")); maps[f].mark("truthKnown") }
        else { message(String(format: L("td.truthPartial"), L("lord.\(f).name"), truthsFound(f))) }
        burst(e.x, e.y - 0.6, yielded ? RGB(r: 220, g: 255, b: 220) : RGB(r: 255, g: 255, b: 255), 24)
        for id in Reign.tributeItems(f) { drops.append(TDDrop(id: id, n: 3, x: e.x, y: e.y)) }
        drops.append(TDDrop(id: Item.lightShard, n: 1, x: e.x, y: e.y))
        sfx(yielded ? .heal : .die)
    }

    // MARK: combat

    /// A little fountain of sparks: a lamp lit, a spring taken, a creature gone.
    func burst(_ x: Double, _ y: Double, _ c: RGB, _ n: Int) {
        for _ in 0..<n { let a = Double.random(in: 0..<(2 * .pi)), v = Double.random(in: 1.5...4); particles.append(Particle(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v - 4, t: 0.8, life: 0.8, color: c)) }
    }

    /// Space: one swing in an arc in front. With no cursor to aim, the swing turns toward the nearest creature in reach.
    func attack() {
        guard dead <= 0 else { return }
        attackCD = TDGame.attackCooldown
        let reach = 1.7
        if let e = enemies.filter({ hypot($0.x - px, $0.y - py) < reach + $0.radius }).min(by: { hypot($0.x - px, $0.y - py) < hypot($1.x - px, $1.y - py) }) {
            let d = max(0.01, hypot(e.x - px, e.y - py)); fx = (e.x - px) / d; fy = (e.y - py) / d
            if fx != 0 { face = fx > 0 ? 1 : -1 }
        }
        slashT = 0.18; slashX = fx; slashY = fy; swing = 0.2; sfx(.swing)
        let dmg = jar.strike + (altarLit("R") ? 6 : 0)
        for e in enemies {
            let dx = e.x - px, dy = e.y - py, d = hypot(dx, dy)
            guard d < reach + e.radius else { continue }
            if d > 0.3 && (dx * fx + dy * fy) / d < 0.35 { continue }      // about 140 degrees in front
            hit(e, dmg)
        }
    }

    /// Shift: a short roll in the way you are moving (or facing), untouchable while it lasts.
    func dodge() {
        guard dead <= 0, dodgeCD <= 0, dodgeT <= 0 else { return }
        var vx = 0.0, vy = 0.0
        if input.left { vx -= 1 }; if input.right { vx += 1 }; if input.up { vy -= 1 }; if input.down { vy += 1 }
        if vx == 0 && vy == 0 { vx = -fx; vy = -fy }       // standing still: step back from what you face
        let l = max(0.01, hypot(vx, vy)); dodgeX = vx / l; dodgeY = vy / l
        dodgeT = TDGame.dodgeTime; dodgeCD = TDGame.dodgeCooldown; iframe = max(iframe, 0.3); sfx(.pick)
    }

    func hit(_ e: TDEnemy, _ dmg: Int) {
        e.hp -= dmg; e.hurt = 0.2; focus = e; hitStop = 0.05; shake = max(shake, 0.12)
        for _ in 0..<5 { particles.append(Particle(x: e.x, y: e.y - 0.4, vx: Double.random(in: -4...4), vy: Double.random(in: -5 ... -1), t: 0.35, life: 0.35, color: RGB(r: 255, g: 245, b: 210))) }
        let a = atan2(e.y - py, e.x - px)
        if e.kind != .lord { e.x += cos(a) * 0.6; e.y += sin(a) * 0.6 }
        floats.append(FloatText(x: e.x, y: e.y - 1, t: 0.8, text: "-\(dmg)", color: RGB(r: 255, g: 255, b: 255)))
        if e.kind == .lord, !e.pleaded, e.hp * 2 < e.maxhp, let f = e.lordFloor {
            e.pleaded = true; message(L("lord.\(f).plea"))
            if lordYields(e) { return }
        }
        if e.hp <= 0 { kill(e) }
    }

    private func kill(_ e: TDEnemy) {
        enemies.removeAll { $0 === e }; sfx(.die)
        burst(e.x, e.y - 0.3, RGB(r: 255, g: 255, b: 255), 8)
        for _ in 0..<10 { particles.append(Particle(x: e.x, y: e.y - 0.4, vx: Double.random(in: -3...3), vy: Double.random(in: -6 ... -1), t: 0.7, life: 0.7, color: RGB(r: 200, g: 220, b: 210))) }
        if e.lordFloor != nil {
            settleLord(e, yielded: false)
        } else if Double.random(in: 0..<1) < 0.4 {
            drops.append(TDDrop(id: e.kind == .slime ? Item.gel : Item.potion, n: 1, x: e.x, y: e.y))
        }
    }

    func damagePlayer(_ n: Int) {
        guard iframe <= 0, dead <= 0 else { return }
        let ward = jar.ward
        hp -= max(1, Int(Double(n) * (1 - ward))); iframe = 0.8; hurtFlash = 0.35; sfx(.hurt)
        floats.append(FloatText(x: px, y: py - 1.6, t: 1, text: "-\(n)", color: RGB(r: 255, g: 107, b: 107)))
        if hp <= 0 { dead = 2; sfx(.die); message(L("td.fell")) }
    }

    private func revive() {
        hp = maxhp
        let p = map.up
        px = Double(p.x) + 0.5; py = Double(p.y) + 1.5
        if map.blocks(Int(px), Int(py)) { py = Double(p.y) + 0.5; px = Double(p.x) + 1.5 }
        stairCooldown = 1.5
    }

    private func updateEnemies(_ dt: Double) {
        for e in enemies {
            e.t += dt; e.hurt = max(0, e.hurt - dt)
            let dx = px - e.x, dy = py - e.y, d = hypot(dx, dy)
            if e.kind == .lord { lordNotices(e, d) }
            var sees = d < (covered ? 2.5 : 9) || (e.kind == .lord && d < 12)
            var vx = 0.0, vy = 0.0
            if let c = campFire, hypot(e.x - Double(c.x) - 0.5, e.y - Double(c.y) - 0.5) < 8 || inCamp {
                sees = false                                                        // the fire keeps them off
                let ax = e.x - Double(c.x) - 0.5, ay = e.y - Double(c.y) - 0.5, l = max(0.1, hypot(ax, ay))
                if l < 8 { vx = ax / l; vy = ay / l }
            }
            if sees && d > 0.1 { vx = dx / d; vy = dy / d }
            else if vx == 0 && vy == 0 { vx = cos(e.t * 0.7 + Double(e.id.hashValue % 7)); vy = sin(e.t * 0.5) }
            var sp = e.speed * (sees ? 1 : 0.35)
            if e.kind == .slime { sp *= 0.4 + 1.2 * max(0, sin(e.t * 5)) }
            if e.kind == .lord && sees && Int(e.t * 10) % 40 < 8 { sp *= 3 }      // a charge every few seconds
            if vx != 0 { e.face = vx > 0 ? 1 : -1 }
            moveEnemy(e, vx * sp * dt, 0); moveEnemy(e, 0, vy * sp * dt)
            if d < 0.5 + e.radius && iframe <= 0 && dead <= 0 && !inCamp {
                damagePlayer(e.dmg); focus = focus ?? e
                // knocked back a step, so a hit gives room to answer
                let k = max(0.01, d); tryMove(dx: dx / k * 0.7, dy: 0); tryMove(dx: 0, dy: dy / k * 0.7)
            }
        }
    }
    private func moveEnemy(_ e: TDEnemy, _ dx: Double, _ dy: Double) {
        let r = e.kind == .lord ? 1.0 : 0.3, nx = e.x + dx, ny = e.y + dy
        if e.kind != .bat {
            for y in Int(Foundation.floor(ny - r * 0.6))...Int(Foundation.floor(ny + r * 0.6)) { for x in Int(Foundation.floor(nx - r))...Int(Foundation.floor(nx + r)) where map.blocks(x, y) { return } }
        } else if map.blocks(Int(Foundation.floor(nx)), Int(Foundation.floor(ny))) { return }
        e.x = nx; e.y = ny
    }

    private func updateDrops(_ dt: Double) {
        for i in drops.indices.reversed() {
            drops[i].t += dt
            let d = hypot(drops[i].x - px, drops[i].y - py)
            if d < 3 && drops[i].t > 0.3 { drops[i].x += (px - drops[i].x) * dt * 6; drops[i].y += (py - drops[i].y) * dt * 6 }
            if d < 0.6 && drops[i].t > 0.3 {
                let s = drops[i]
                if addItem(s.id, s.n) { drops.remove(at: i); sfx(.pick); floats.append(FloatText(x: px, y: py - 1.6, t: 0.9, text: "+\(s.n) \(itemName(s.id))", color: RGB(r: 255, g: 224, b: 138))) }
            }
        }
    }

    // MARK: the jar

    func feed() {
        guard let s = held else { tip("손에 든 것이 없습니다"); return }
        if let why = jar.acceptReason(s.id) { tip(why); return }
        let what = jar.feed(s.id); remove(s.id, 1); sfx(.heal)
        gain(energyFor(s.id))
        message("\(itemName(s.id)) → \(jar.named): \(what) (\(jar.colorName))")
    }
    func energyFor(_ id: Int) -> Double {
        switch id { case Tile.redSpore, Tile.greenSpore, Tile.blueSpore: return 30; case Tile.iron, Tile.gold, Item.diamond: return 15; case Item.gel: return 10; default: return 8 }
    }
    func useHeld() {
        guard let s = held, let it = ITEMS[s.id], let u = it.use else { return }
        switch u {
        case .heal: if hp >= maxhp { tip("체력이 가득 찼습니다"); return }; hp = min(maxhp, hp + 60); message("체력 +60")
        case .life: maxhp += 20; hp += 20; gain(Game.shardGain); message(L("shard.used"))
        case .armor: return
        }
        remove(s.id, 1); sfx(.heal)
    }
    func gain(_ n: Double) {
        let b = jar.energy; jar.energy += n
        let got = Int((jar.energy - b).rounded())
        if got > 0 { floats.append(FloatText(x: px, y: py - 2, t: 1.2, text: String(format: L("energy.gain"), got), color: RGB(r: 240, g: 250, b: 200))) }
    }
    func spend(_ n: Double) -> Bool {
        guard jar.energy >= n else { tip(String(format: L("energy.notEnough"), Int(n))); return false }
        jar.energy -= n; return true
    }
    private func updateEnergy(_ dt: Double) {
        var drain = covered ? 0 : Game.glowDrain
        if lensActive { drain += Game.lensDrain }
        jar.energy -= drain * dt
        if jar.energy < 0.5 && lensActive { lensActive = false; tip(L("energy.lensOff")) }
        let low = jar.energy < jar.energyCap * 0.2
        if low && !warnedLow { warnedLow = true; tip(L("energy.low")) }
        if !low { warnedLow = false }
    }
    func toggleCover() { covered.toggle(); sfx(.pick); if covered { tip(L("cover.first")) } }
    func cycleLens() {
        if !lensActive { lensActive = true; lens = .path } else if lens == .hidden { lensActive = false } else { lens = Lens(rawValue: lens.rawValue + 1) ?? .path }
        if lensActive && jar.energy < 0.5 { lensActive = false; tip(L("energy.lensOff")); return }
        sfx(.pick)
        tip(lensActive ? String(format: L("lens.switched"), L(lens.titleKey), L(lens.titleKey + ".what")) : L("lens.off"))
    }
    func selectLens(_ m: Lens) {
        sfx(.pick)
        if lensActive && lens == m { lensActive = false; tip(L("lens.off")); return }
        if jar.energy < 0.5 { tip(L("energy.lensOff")); return }
        lens = m; lensActive = true; tip(String(format: L("lens.switched"), L(lens.titleKey), L(lens.titleKey + ".what")))
    }
    var lensRadius: Int { (18 + jar.brightness) * (lens.boosted(by: jar) ? 3 : 2) / 2 }
    func lensMarks() -> [(x: Int, y: Int, kind: Int)] {
        guard lensActive else { return [] }
        let r = lensRadius, cx = Int(Foundation.floor(px)), cy = Int(Foundation.floor(py)), m0 = map
        let ores: Set<Int> = [Tile.coal, Tile.iron, Tile.gold, Tile.diamondOre]
        let hidden: Set<Int> = [Tile.chest, Tile.throne, Tile.core]
        let paths: Set<Int> = [Tile.crack, Tile.stairsDown, Tile.stairsUp, Tile.lightSpring]
        var out: [(Int, Int, Int)] = []
        for y in max(0, cy - r)...min(map.h - 1, cy + r) { for x in max(0, cx - r)...min(map.w - 1, cx + r) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r {
            let t = map.get(x, y)
            switch lens {
            case .ore: if ores.contains(t) { out.append((x, y, t)) }
            case .hidden: if hidden.contains(t) || (t == Tile.propBlock && m0.props.contains { $0.x == x && $0.y == y && $0.kind.hasPrefix("truth") }) { out.append((x, y, t == Tile.propBlock ? Tile.chest : t)) }; if let b = map.buried, b.x == x, b.y == y { out.append((x, y, Tile.chest)) }
            case .path: if paths.contains(t) { out.append((x, y, t)) }
            }
        } }
        return out
    }

    // MARK: grandmother's errand (floor 0)

    func lit(_ i: Int) -> Bool { maps[0].houses.indices.contains(i) && maps[0].get(maps[0].houses[i].x, maps[0].houses[i].y) == Tile.lantern }
    var housesLit: Int { maps[0].houses.indices.filter { lit($0) }.count }
    var jarLooked = false

    private func updateErrand(_ dt: Double) {
        guard !disaster else { return }
        flickerT -= dt
        if step >= Tutorial.done {
            calm -= dt
            if calm <= 0 { strike() }
            return
        }
        switch step {
        case Tutorial.look: if jarLooked { advance() }
        case Tutorial.houseA: if lit(0) { advance() }
        case Tutorial.box: if maps[0].buried == nil && maps[0].chests.isEmpty { advance() }
        case Tutorial.feed: if jar.sporeG { advance() }
        case Tutorial.houseB: if lit(1) { advance() }
        case Tutorial.cover:
            if floor == 0 && !enemies.contains(where: { $0.kind == .starved }) {
                let h = maps[0].houses[2]; enemies.append(TDEnemy(.starved, x: Double(h.x) - 6.5, y: Double(h.y) + 6.5, floor: 1))
            }
            if covered { coverSeen = true } else if coverSeen { advance() }
        case Tutorial.houseC: if lit(2) { advance() }
        default: break
        }
    }
    var coverSeen = false
    private func advance() {
        step += 1; sfx(.pick)
        if step >= Tutorial.done { calm = 6; message(L("errand.childMissing")); enemies.removeAll { $0.kind == .starved } }
    }
    func skipErrand() { guard !disaster, step < Tutorial.done else { return }; step = Tutorial.done; calm = 3 }

    /// The disaster: the mist is pulled underground and a crack opens where grandmother stood.
    private func strike() {
        disaster = true
        let g = maps[0].grandma
        let c = TDPoint(x: g.x + 2, y: g.y - 3)
        for y in (c.y - 1)...(c.y + 1) { for x in (c.x - 1)...(c.x + 1) where maps[0].get(x, y) == Tile.trunk || maps[0].get(x, y) == Tile.flower { maps[0].set(x, y, Tile.air) } }
        maps[0].set(c.x, c.y, Tile.stairsDown); maps[0].down = c
        onTile?(); sfx(.roar)
        message(L("td.disaster"))
        if let t = Stage.title(9) { onStage?(t.number, t.name, t.line) }
    }
    var onStage: ((String, String, String) -> Void)?

    /// What to do now, and the long goal under it.
    var objective: (title: String, detail: String) {
        if !disaster && step < Tutorial.done {
            var detail = L("step.\(step).detail")
            let targets: [Int: TDPoint] = [Tutorial.houseA: maps[0].houses[0], Tutorial.box: maps[0].buried ?? maps[0].houses[0], Tutorial.houseB: maps[0].houses[1], Tutorial.cover: maps[0].houses[2], Tutorial.houseC: maps[0].houses[2]]
            if floor == 0, let t = targets[step] { detail += " · " + direction(to: t) }
            return (String(format: L("objective.step"), step + 1, Tutorial.done, L("step.\(step).title")), detail)
        }
        if let d = map.down {
            let sealed = floor >= 5 && [(0, 1), (1, 0), (-1, 0), (0, -1)].contains { map.get(d.x + $0.0, d.y + $0.1) == Tile.crack }
            return (L(floor == 0 ? "objective.descend" : "td.findStairs"), (sealed ? L("td.sealed") + " · " : "") + (map.explored[d.y * map.w + d.x] != 0 || floor == 0 ? direction(to: d) : L("td.useLens")))
        }
        return (L("td.heart"), L("td.coreNeedsWhite"))
    }
    var progress: String {
        if !disaster { return String(format: L("progress.errand"), housesLit, 3) }
        if Reign.floors.contains(floor) { return String(format: L("progress.descent"), max(1, seen.max() ?? 1)) + " · " + String(format: L("td.truthProgress"), truthsFound(floor)) }
        return String(format: L("progress.descent"), max(1, seen.max() ?? 1))
    }
    func direction(to t: TDPoint) -> String {
        let dx = t.x - Int(Foundation.floor(px)), dy = t.y - Int(Foundation.floor(py))
        var parts: [String] = []
        if abs(dx) > 1 { parts.append(String(format: L(dx > 0 ? "dir.right" : "dir.left"), abs(dx))) }
        if abs(dy) > 1 { parts.append(String(format: L(dy > 0 ? "td.dirDown" : "td.dirUp"), abs(dy))) }
        return parts.isEmpty ? L("td.here") : parts.joined(separator: " ")
    }

    /// Light for the map: ambient by floor, every glowing tile, and the jar around the player.
    func light() -> (r: [UInt8], g: [UInt8], b: [UInt8]) {
        let m = map, n = m.w * m.h
        var r = [UInt8](repeating: 0, count: n), g = r, b = r
        var srcs: [(Int, Int, Int, Int, Int)] = []
        let amb: RGB = floor == 0 ? (disaster ? RGB(r: 8, g: 9, b: 11) : RGB(r: 14, g: 14, b: 13)) : (Reign.floors.contains(floor) ? Stage.sky(floor).light : RGB(r: 9, g: 9, b: 10))
        // underground there is no ambient light: only what you have seen stays, dimly, in the floor's own tint
        let mem = RGB(r: 3, g: 3, b: 4), sky = RGB(r: max(3, amb.r * 6 / 10), g: max(3, amb.g * 6 / 10), b: max(3, amb.b * 6 / 10))
        for y in 0..<m.h { for x in 0..<m.w {
            let t = m.get(x, y)
            // floors 1...4: only what you have seen stays, dimly. Floors 5...9 lie under their own sky: a faint light over all the hall
            let open = !m.blocks(x, y) || t == Tile.water
            if floor >= 5 && open { srcs.append((x, y, sky.r, sky.g, sky.b)) }
            else if floor > 0 && open && m.explored[y * m.w + x] != 0 { srcs.append((x, y, mem.r, mem.g, mem.b)) }
            if let l = TILES[t].light, !((t == Tile.torch || t == Tile.lantern) && floor >= 8) { srcs.append((x, y, l.r, l.g, l.b)) }
            if t == Tile.stairsDown || t == Tile.stairsUp { srcs.append((x, y, 6, 7, 8)) }
        } }
        if floor == 0 { for y in 0..<m.h { for x in 0..<m.w { srcs.append((x, y, amb.r, amb.g, amb.b)) } } }
        for p in m.props where p.kind == "lantern" { srcs.append((p.x, p.y, 13, 14, 11)) }
        for p in m.props where p.kind == "oldTorch" { srcs.append((p.x, p.y, 5, 10, 10)) }     // grandmother's mist, teal
        for p in m.props {
            switch p.kind {
            case "campfire": srcs.append((p.x, p.y, 14, 10, 5))
            case let k where k.hasPrefix("tent") && altarLit(String(k.dropFirst(4))): srcs.append((p.x, p.y, 9, 8, 6))
            case let k where k.hasPrefix("altar") && altarLit(String(k.dropFirst(5))):
                let c = ["R": (9, 4, 3), "G": (4, 9, 4), "B": (3, 6, 10)][String(k.dropFirst(5))] ?? (6, 6, 6); srcs.append((p.x, p.y, c.0, c.1, c.2))
            case "gateG": srcs.append((p.x, p.y, 2, 6, 2))
            case "gateR": srcs.append((p.x, p.y, 6, 2, 1))
            case "gateB": srcs.append((p.x, p.y, 1, 3, 7))
            default: break
            }
        }
        // the deeper the floor, the more of the jar's light the dark swallows
        let absorb = floor == 0 ? 1.0 : max(0.62, 1 - Double(floor) * 0.042)
        let base = jar.light, lift = springGlowT > 0 ? 6 : 3, k = (covered ? 0.15 : (jar.energy < 0.5 ? 0.35 : 1.0)) * absorb
        func ch(_ v: Int) -> Int { Int(Double(max(9, min(15, v + lift))) * k) }
        srcs.append((Int(Foundation.floor(px)), Int(Foundation.floor(py)), ch(base.r), ch(base.g), ch(base.b)))
        for c in 0..<3 {
            var arr = [UInt8](repeating: 0, count: n); var q: [Int] = []
            for s in srcs { let v = UInt8(max(0, min(15, c == 0 ? s.2 : (c == 1 ? s.3 : s.4)))); let i = s.1 * m.w + s.0; if v > arr[i] { arr[i] = v; q.append(i) } }
            var head = 0
            while head < q.count {
                let i = q[head]; head += 1
                let v = Int(arr[i]); if v <= 1 { continue }
                let x = i % m.w, y = i / m.w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard m.inside(nx, ny) else { continue }
                    let j = ny * m.w + nx, nv = v - (m.blocks(nx, ny) ? 3 : 1)
                    if nv > Int(arr[j]) { arr[j] = UInt8(nv); q.append(j) }
                }
            }
            if c == 0 { r = arr } else if c == 1 { g = arr } else { b = arr }
        }
        // only live light makes memory, not memory itself
        for i in 0..<n where Int(r[i]) + Int(g[i]) + Int(b[i]) > 18 { m.explored[i] = 1 }
        return (r, g, b)
    }
}
