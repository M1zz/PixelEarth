import Foundation

/// Ruling a floor plays as tower defense: waves march on the throne, you build and fight, then the challenger comes.
struct Turret { var x: Int; var y: Int; var cooldown = 0.0 }

final class Defense {
    let floor: Int, level: Int, waves: Int
    var wave = 0
    var queue: [EnemyType] = []
    var spawnT = 0.0, gapT: Double
    var throneHP: Double, throneMax: Double
    var points: Int
    var turrets: [Turret] = []
    var walls = Set<Int>()      // tile keys of placed barricades; attackers break only these
    var bossStarted = false
    init(floor: Int, level: Int) {
        self.floor = floor; self.level = level
        waves = DefenseDesign.waves(level)
        gapT = DefenseDesign.prepTime
        throneMax = DefenseDesign.throneHP(level); throneHP = throneMax
        points = DefenseDesign.startPoints(level)
    }
}

/// The difficulty curve in one place. Level = 2 per floor below 5, plus 1 per successful defense.
enum DefenseDesign {
    static let prepTime = 20.0
    static let turretCost = 30, wallCost = 5, maxTurrets = 6
    static let turretRange = 11.0

    static func level(floor: Int, defenses: Int) -> Int { (floor - 5) * 2 + defenses + 1 }
    /// 1 Skirmish (1-2), 2 Raid (3-5), 3 Assault (6-9), 4 War (10-14), 5 Doom (15+)
    static func tier(_ level: Int) -> Int { level <= 2 ? 1 : (level <= 5 ? 2 : (level <= 9 ? 3 : (level <= 14 ? 4 : 5))) }
    static func waves(_ level: Int) -> Int { min(7, 3 + level / 3) }
    static func throneHP(_ level: Int) -> Double { 100 + Double(level) * 15 }
    static func startPoints(_ level: Int) -> Int { 40 + level * 12 }
    static func budget(level: Int, wave: Int) -> Int { Int(Double(5 + level * 3) * (1 + 0.35 * Double(wave))) }
    static func spawnGap(_ level: Int) -> Double { max(0.45, 1.3 - Double(level) * 0.06) }
    static func waveGap(_ level: Int) -> Double { max(6, 14 - Double(level) * 0.6) }
    static func enemyHP(_ base: Int, level: Int) -> Int { Int(Double(base) * (1 + 0.12 * Double(level - 1))) }
    static func enemyDamage(_ base: Int, level: Int) -> Int { Int(Double(base) * (1 + 0.08 * Double(level - 1))) }
    static func turretDamage(_ level: Int) -> Int { 10 + level * 3 }
    /// Each attacker: what it costs from a wave's budget, the level it first appears, and its blow against the throne.
    /// Bats arrive at level 3 to fly over walls; cave slimes at 7 hit hard enough that walls alone stop being enough.
    static let roster: [(type: EnemyType, cost: Int, from: Int, throneHit: Double)] = [
        (.slime, 1, 1, 3), (.zombie, 3, 2, 6), (.bat, 2, 3, 4), (.ice, 2, 5, 5), (.cave, 4, 7, 10),
    ]
    static func compose(level: Int, wave: Int) -> [EnemyType] {
        var left = budget(level: level, wave: wave), out: [EnemyType] = []
        let open = roster.filter { $0.from <= level }
        while let pick = open.filter({ $0.cost <= left }).randomElement() { out.append(pick.type); left -= pick.cost }
        return out
    }
    static func cost(_ t: EnemyType) -> Int { roster.first { $0.type == t }?.cost ?? 1 }
    static func throneHit(_ t: EnemyType) -> Double { roster.first { $0.type == t }?.throneHit ?? 3 }
}

extension Game {
    private func wallKey(_ x: Int, _ y: Int) -> Int { y * world.w + x }
    private var attackersAlive: Bool { enemies.contains { $0.attackerCost > 0 } }

    func startDefense(_ r: FloorReign) {
        guard defense == nil else { return }
        let level = DefenseDesign.level(floor: r.floor, defenses: r.defenses)
        defense = Defense(floor: r.floor, level: level)
        sfx(.roar); onStoryEvent?("tremor")
        message(String(format: L("defense.start"), level, L("defense.tier.\(DefenseDesign.tier(level))"), Int(DefenseDesign.prepTime)))
    }

    func updateDefense(_ dt: Double) {
        guard let d = defense else { return }
        let t = Reign.thronePosition(d.floor, worldWidth: world.w)
        if d.throneHP <= 0 { loseThrone(d.floor); return }
        let rangeSq = DefenseDesign.turretRange * DefenseDesign.turretRange
        for i in d.turrets.indices {
            d.turrets[i].cooldown -= dt
            guard d.turrets[i].cooldown <= 0 else { continue }
            let tx = Double(d.turrets[i].x) + 0.5, ty = Double(d.turrets[i].y) + 0.4
            var best: Enemy? = nil, bd = rangeSq
            for e in enemies {
                let ds = pow(e.x - tx, 2) + pow(e.y + e.h / 2 - ty, 2)
                if ds < bd { bd = ds; best = e }
            }
            guard let e = best else { continue }
            d.turrets[i].cooldown = 0.8
            let a = atan2(e.y + e.h / 2 - ty, e.x - tx)
            arrows.append(Arrow(x: tx, y: ty, vx: cos(a) * 26, vy: sin(a) * 26, t: 1, dmg: DefenseDesign.turretDamage(d.level)))
            sfx(.bow)
        }
        if d.bossStarted { return }
        if let next = d.queue.first {
            d.spawnT -= dt
            if d.spawnT <= 0 {
                d.queue.removeFirst(); d.spawnT = DefenseDesign.spawnGap(d.level)
                spawnAttacker(next, d, t)
            }
        } else if !attackersAlive {
            if d.wave >= d.waves {
                if boss == nil, let i = reignIndex(d.floor) { d.bossStarted = true; wakeChallenger(reigns[i], at: t) }
                return
            }
            d.gapT -= dt
            if d.gapT <= 0 {
                d.queue = DefenseDesign.compose(level: d.level, wave: d.wave)
                d.wave += 1; d.gapT = DefenseDesign.waveGap(d.level); d.spawnT = 0
                sfx(.roar); message(String(format: L("defense.wave"), d.wave, d.waves))
            }
        }
    }

    private func spawnAttacker(_ type: EnemyType, _ d: Defense, _ t: (x: Int, y: Int)) {
        let side: Double = Bool.random() ? -1 : 1
        let e = Enemy(type: type, x: Double(t.x) + side * 12, y: Double(t.y) - (type == .bat ? 5 : 2))
        e.attackerCost = DefenseDesign.cost(type); e.t = 0
        e.maxhp = DefenseDesign.enemyHP(e.maxhp, level: d.level); e.hp = e.maxhp
        e.dmg = DefenseDesign.enemyDamage(e.dmg, level: d.level)
        enemies.append(e)
    }

    /// Attackers go for the throne, breaking only the barricades in their way.
    func marchAttacker(_ e: Enemy, _ dt: Double) {
        guard let d = defense else { e.attackerCost = 0; return }
        let t = Reign.thronePosition(d.floor, worldWidth: world.w)
        let tx = Double(t.x) + 0.5, dir: Double = tx >= e.x ? 1 : -1
        e.face = dir
        if abs(tx - e.x) < 1.4 + e.w / 2 && (e.fly ? abs(Double(t.y) - e.y) < 3 : true) {
            e.vx *= 0.5
            if e.fly { e.vy *= 0.5 }
            if e.t > 1 {
                e.t = 0; d.throneHP -= DefenseDesign.throneHit(e.type); sfx(.hit)
                for _ in 0..<4 { particles.append(Particle(x: tx, y: Double(t.y) + 0.5, vx: Double.random(in: -4...4), vy: Double.random(in: -6 ... -1), t: 0.4, life: 0.4, color: RGB(r: 255, g: 210, b: 110))) }
            }
            return
        }
        if e.fly {
            let sp = 4.5
            e.vx += (dir * sp - e.vx) * dt * 2
            e.vy += ((Double(t.y) - 1 - e.y) * 1.5 + sin(e.t * 6) * 2 - e.vy) * dt * 2
            return
        }
        let ax = Int(floor(e.x + dir * (e.w / 2 + 0.2)))
        let feet = Int(floor(e.y + e.h - 0.2))
        for y in [feet, feet - 1] where d.walls.contains(y * world.w + ax) {
            e.vx *= 0.5
            if e.t > 1.2 {
                e.t = 0; d.walls.remove(y * world.w + ax); setTile(ax, y, Tile.air); spawnDust(ax, y, RGB(r: 133, g: 139, b: 158), 6); sfx(.brk)
            }
            return
        }
        if e.type == .zombie {
            e.vx = dir * 3.4
            if e.ground && world.solid(ax, feet) { e.vy = -11.5 }
        } else if e.ground {
            e.vx *= 0.6
            let period = e.type == .cave ? 1.1 : (e.type == .ice ? 1.3 : 1.5)
            if e.t > period {
                e.t = 0; e.vx = dir * (e.type == .cave ? 7.5 : (e.type == .ice ? 6 : 5)); e.vy = -(e.type == .cave ? 11.5 : 9.5)
            }
        }
    }

    /// B: a turret on the floor in front of the player.
    func buildTurret() {
        guard let d = defense else { return }
        if d.turrets.count >= DefenseDesign.maxTurrets { tip(L("defense.turretMax")); return }
        if d.points < DefenseDesign.turretCost { tip(String(format: L("defense.needPoints"), DefenseDesign.turretCost)); return }
        guard let spot = frontFloor() else { tip(L("defense.noRoom")); return }
        if d.turrets.contains(where: { $0.x == spot.x && $0.y == spot.y }) { tip(L("defense.noRoom")); return }
        d.points -= DefenseDesign.turretCost
        d.turrets.append(Turret(x: spot.x, y: spot.y)); sfx(.place)
    }

    /// V: a barricade three blocks high in front of the player.
    func buildWall() {
        guard let d = defense else { return }
        if d.points < DefenseDesign.wallCost { tip(String(format: L("defense.needPoints"), DefenseDesign.wallCost)); return }
        guard let spot = frontFloor() else { tip(L("defense.noRoom")); return }
        d.points -= DefenseDesign.wallCost
        for dy in 0..<3 where world.get(spot.x, spot.y - dy) == Tile.air {
            setTile(spot.x, spot.y - dy, Tile.brick); d.walls.insert(wallKey(spot.x, spot.y - dy))
        }
        sfx(.place)
    }

    private func frontFloor() -> (x: Int, y: Int)? {
        let x = Int(floor(player.x)) + (player.face >= 0 ? 1 : -1)
        var y = Int(floor(player.y + player.h - 0.3))
        guard world.get(x, y) == Tile.air else { return nil }
        while world.get(x, y + 1) == Tile.air && y < world.h - 2 { y += 1 }
        return (x, y)
    }

    /// Ends the battle: temporary defenses come down, and any attackers still alive go with them.
    func endDefense() {
        guard let d = defense else { return }
        for key in d.walls where world.get(key % world.w, key / world.w) == Tile.brick { setTile(key % world.w, key / world.w, Tile.air) }
        enemies.removeAll { $0.attackerCost > 0 }
        defense = nil
    }

    /// Paid in tribute: holding on with more of the throne left pays more, and harder levels pay more.
    func defenseReward(_ d: Defense, into i: Int) -> Int {
        let share = max(0, d.throneHP / d.throneMax)
        let n = Int((Double(3 + d.level) * (0.5 + share)).rounded())
        for _ in 0..<n {
            let id = Reign.tributeItems(d.floor).randomElement()!
            reigns[i].tribute[id] = min(Reign.tributeCap, (reigns[i].tribute[id] ?? 0) + 1)
        }
        return n
    }
}
