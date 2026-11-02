import Foundation

/// Who holds a floor's throne. Each floor passes through: a lord rules -> beaten, empty -> claimed by the player or retaken by a stronger lord.
enum ThroneState: Int, Codable { case lord, vacant, player }

struct FloorReign: Codable {
    var floor: Int
    var state = ThroneState.lord
    var generation = 1          // grows with every succession and every defended challenge; sets lord strength
    var nameIndex = 0
    var defenses = 0
    var tribute: [Int: Int] = [:]
    var stolen: [Int: Int] = [:]    // what the current lord took from the player; returned when beaten
    var tributeT = 0.0
    var vacantT = 0.0
    /// Set once a lord of this floor has been beaten: the throne record then shows the founder's true story. Optional so older saves load.
    var truthKnown: Bool? = nil
}

struct Siege: Codable { var floor: Int; var timeLeft: Double }

enum Reign {
    static let floors = [5, 6, 7, 8, 9]
    static let nameCount = 8
    /// An empty throne does not stay empty.
    static let vacantTime = 300.0
    static let tributeInterval = 30.0, tributeCap = 40
    static let siegeWarning = 90.0
    static let siegeInterval = 150.0...240.0
    /// Benefits on a floor you rule.
    static let mineBonus = 1.3, damageTaken = 0.85
    /// A lord wakes when you come this close to its throne, and rests when you leave this far.
    static let wakeRange = 24.0, restRange = 60.0

    static func baseHP(_ floor: Int) -> Int { [5: 320, 6: 520, 7: 800, 8: 1150, 9: 1600][floor] ?? 320 }
    static func baseDamage(_ floor: Int) -> Int { [5: 20, 6: 28, 7: 38, 8: 48, 9: 60][floor] ?? 20 }
    static func hp(_ floor: Int, generation g: Int) -> Int { Int(Double(baseHP(floor)) * (1 + 0.4 * Double(g - 1))) }
    static func damage(_ floor: Int, generation g: Int) -> Int { Int(Double(baseDamage(floor)) * (1 + 0.2 * Double(g - 1))) }
    /// Seconds between leaps; later generations barely pause.
    static func leapPeriod(generation g: Int) -> Double { max(0.7, 1.5 / (1 + 0.12 * Double(g - 1))) }
    static func tint(_ floor: Int) -> RGB {
        [5: RGB(r: 110, g: 220, b: 120), 6: RGB(r: 255, g: 95, b: 90), 7: RGB(r: 90, g: 150, b: 255), 8: RGB(r: 150, g: 110, b: 200), 9: RGB(r: 255, g: 240, b: 190)][floor] ?? RGB(r: 255, g: 255, b: 255)
    }
    static func tributeItems(_ floor: Int) -> [Int] {
        switch floor {
        case 5: return [Tile.greenSpore, Item.gel, Tile.iron]
        case 6: return [Tile.redSpore, Tile.iron, Tile.gold]
        case 7: return [Tile.blueSpore, Tile.gold, Item.potion]
        case 8: return [Tile.gold, Tile.iron, Item.diamond]
        default: return [Tile.gold, Item.diamond, Item.lightShard]
        }
    }
    /// Throne position, on the floor row of the lair. Fixed, so old saves can gain lairs on load.
    static func thronePosition(_ floor: Int, worldWidth w: Int) -> (x: Int, y: Int) {
        let cx = w / 2
        switch floor {
        case 5: return (cx - 48, Layers.campBottom - 1)
        case 6: return (cx + 55, Layers.redTop + 15)
        case 7: return (cx - 60, Layers.blueTop + 14)
        case 8: return (cx + 60, Layers.darkTop + 14)
        default: return (cx - 50, Layers.cityTop + 9)
        }
    }
}

extension World {
    /// Carves any lair not yet in the world. Safe to call on every load.
    func ensureLairs() {
        for f in Reign.floors {
            let t = Reign.thronePosition(f, worldWidth: w)
            if get(t.x, t.y) == Tile.throne { continue }
            let rx = 14.0, ry = 6.0, cy = Double(t.y - 3)
            for y in (t.y - 10)...(t.y + 3) { for x in (t.x - 18)...(t.x + 18) {
                let d = pow(Double(x - t.x) / rx, 2) + pow((Double(y) - cy) / ry, 2)
                let cur = get(x, y)
                if cur == Tile.crystal || cur == Tile.pedestal || cur == Tile.core { continue }
                if y > t.y { if d < 1.9 { set(x, y, Tile.brick) } }
                else if d <= 1 { set(x, y, Tile.air) }
                else if d <= 1.45 { set(x, y, Tile.brick) }
            } }
            for dx in [-9, 9] { set(t.x + dx, t.y, Tile.lantern) }
            set(t.x, t.y, Tile.throne)
            // The first lair opens off the camp, so the player meets the system without digging.
            if f == 5 {
                for x in (t.x + 12)...(campX - 19) { for y in (t.y - 3)...t.y where get(x, y) != Tile.pedestal { set(x, y, Tile.air) }; set(x, t.y + 1, Tile.brick) }
            }
        }
    }
}

extension Game {
    func reignIndex(_ floor: Int) -> Int? { reigns.firstIndex { $0.floor == floor } }
    var currentFloor: Int { Layers.index(forY: Int(floor(player.y))) }
    var rulesCurrentFloor: Bool { reignIndex(currentFloor).map { reigns[$0].state == .player } ?? false }

    static func freshReigns() -> [FloorReign] {
        Reign.floors.map { FloorReign(floor: $0, nameIndex: Int.random(in: 0..<Reign.nameCount)) }
    }

    /// The first lord of each floor is its founder, with a story of their own; later lords come from the name pool.
    func lordName(_ r: FloorReign) -> String { String(format: L("reign.lordName"), r.generation, r.generation == 1 ? L("lord.\(r.floor).name") : L("lord.name.\(r.nameIndex)")) }
    func lordCreed(_ r: FloorReign) -> String { r.generation == 1 ? L("lord.\(r.floor).creed") : L("lord.creed.\(r.nameIndex)") }
    func floorName(_ f: Int) -> String { L("floor.\(f)") }

    /// The floor's own light: a throne only accepts someone who carries it.
    func meetsClaimCondition(_ floor: Int) -> Bool {
        switch floor {
        case 5: return jar.isGreen
        case 6: return jar.isRed
        case 7: return jar.isBlue
        case 8: return jar.isViolet
        default: return jar.isWhite
        }
    }

    // MARK: per-frame

    func updateReigns(_ dt: Double) {
        guard disasterStruck else { return }
        for i in reigns.indices {
            switch reigns[i].state {
            case .vacant:
                reigns[i].vacantT -= dt
                if reigns[i].vacantT <= 0 { crownNewLord(i, stolen: [:]); message(String(format: L("reign.retaken"), floorName(reigns[i].floor), lordName(reigns[i]))) }
            case .player:
                reigns[i].tributeT += dt
                if reigns[i].tributeT >= Reign.tributeInterval {
                    reigns[i].tributeT = 0
                    let id = Reign.tributeItems(reigns[i].floor).randomElement()!
                    reigns[i].tribute[id] = min(Reign.tributeCap, (reigns[i].tribute[id] ?? 0) + 1)
                }
            case .lord: break
            }
        }
        updateSiege(dt)
        updateLordPresence()
    }

    private func crownNewLord(_ i: Int, stolen: [Int: Int]) {
        reigns[i].state = .lord
        reigns[i].generation += 1
        reigns[i].nameIndex = (reigns[i].nameIndex + 1 + Int.random(in: 0..<(Reign.nameCount - 1))) % Reign.nameCount
        reigns[i].defenses = 0
        reigns[i].stolen = stolen
        reigns[i].tribute = [:]
        setThroneArt(reigns[i].floor)
    }

    func setThroneArt(_ floor: Int) {
        guard let i = reignIndex(floor) else { return }
        let t = Reign.thronePosition(floor, worldWidth: world.w)
        world.throneCol["\(t.x),\(t.y)"] = reigns[i].state == .vacant ? 0 : (reigns[i].state == .lord ? 1 : 2)
        onTileChanged?(t.x, t.y)
    }

    private func updateSiege(_ dt: Double) {
        let ruled = reigns.filter { $0.state == .player }
        guard !ruled.isEmpty else { siege = nil; nextSiegeT = Double.random(in: Reign.siegeInterval); return }
        if var s = siege {
            // The clock is how long until they arrive; once the player is there, the battle decides it.
            if defense?.floor != s.floor { s.timeLeft -= dt }
            siege = s
            if s.timeLeft <= 0 { loseThrone(s.floor); return }
        } else {
            nextSiegeT -= dt
            if nextSiegeT <= 0, let target = ruled.randomElement() {
                siege = Siege(floor: target.floor, timeLeft: Reign.siegeWarning)
                nextSiegeT = Double.random(in: Reign.siegeInterval)
                sfx(.roar); message(String(format: L("reign.siegeStart"), floorName(target.floor)))
            }
        }
    }

    /// Wakes the lord or challenger when the player comes near, and lets it rest when they leave.
    private func updateLordPresence() {
        if let e = floorLord {
            if !enemies.contains(where: { $0 === e }) { floorLord = nil; return }
            let t = Reign.thronePosition(e.lordFloor ?? 5, worldWidth: world.w)
            if !e.isChallenger && hypot(player.x - Double(t.x), player.y - Double(t.y)) > Reign.restRange {
                enemies.removeAll { $0 === e }; floorLord = nil; if boss === e { boss = nil }
            }
            return
        }
        guard boss == nil, player.dead <= 0 else { return }
        for r in reigns {
            let t = Reign.thronePosition(r.floor, worldWidth: world.w)
            guard hypot(player.x - Double(t.x), player.y - Double(t.y)) < Reign.wakeRange else { continue }
            if r.state == .lord { wakeLord(r, challenger: false, at: t); return }
            if r.state == .player, siege?.floor == r.floor { startDefense(r); return }
        }
    }

    func wakeChallenger(_ r: FloorReign, at t: (x: Int, y: Int)) { wakeLord(r, challenger: true, at: t) }

    /// Challengers go for the throne unless the player stands close enough to pick the fight.
    func lordDirection(_ e: Enemy, playerSign: Double) -> Double {
        guard e.isChallenger, let f = e.lordFloor, hypot(player.x - e.x, player.y - e.y) > 8 else { return playerSign }
        return Double(Reign.thronePosition(f, worldWidth: world.w).x) >= e.x ? 1 : -1
    }

    private func wakeLord(_ r: FloorReign, challenger: Bool, at t: (x: Int, y: Int)) {
        let g = challenger ? r.generation + 1 : r.generation
        let e = Enemy(type: .king, x: Double(t.x) + (player.x < Double(t.x) ? 5 : -5), y: Double(t.y) - 4)
        e.lordFloor = r.floor; e.isChallenger = challenger; e.generation = g
        e.maxhp = Reign.hp(r.floor, generation: g); e.hp = e.maxhp; e.dmg = Reign.damage(r.floor, generation: g)
        let scale = min(1.5, 0.85 + 0.08 * Double(g))
        e.w *= scale; e.h *= scale; e.drawScale = scale
        enemies.append(e); boss = e; floorLord = e; sfx(.roar)
        if challenger {
            message(String(format: L("reign.challengerHere"), g)); message(L("lord.\(r.floor).challenger"))
        } else {
            message(String(format: L("reign.lordWakes"), lordName(r))); message(lordCreed(r))
        }
    }

    var bossDisplayName: String {
        guard let e = boss, let f = e.lordFloor, let i = reignIndex(f) else { return L("boss.king") }
        return e.isChallenger ? String(format: L("reign.challengerName"), e.generation) : lordName(reigns[i])
    }

    /// Later generations fight differently, not only harder.
    func lordTactics(_ e: Enemy, _ dt: Double) {
        let g = e.generation
        // The founder speaks once when the fight turns against them.
        if !e.isChallenger && !e.pleaded && g == 1, let f = e.lordFloor, e.hp * 2 < e.maxhp { e.pleaded = true; message(L("lord.\(f).plea")) }
        if e.isChallenger, let d = defense, e.ground, e.landedVy > 4 {
            let t = Reign.thronePosition(d.floor, worldWidth: world.w)
            if abs(Double(t.x) + 0.5 - e.x) < e.w / 2 + 2 { d.throneHP -= 6 + Double(g); sfx(.hit) }
        }
        if g >= 2 {
            e.summonT -= dt
            if e.summonT <= 0 && enemies.count < 12 {
                e.summonT = 7
                let s = Enemy(type: .slime, x: e.x + Double.random(in: -2...2), y: e.y); s.vy = -8; enemies.append(s)
            }
        }
        if g >= 4 && e.landedVy > 8 {
            for _ in 0..<14 { particles.append(Particle(x: e.x + Double.random(in: -4...4), y: e.y + e.h, vx: Double.random(in: -6...6), vy: Double.random(in: -6 ... -1), t: 0.5, life: 0.5, color: Reign.tint(e.lordFloor ?? 5))) }
            if player.ground && abs(player.x - e.x) < e.w / 2 + 3 && abs(player.y + player.h - (e.y + e.h)) < 2 { damagePlayer(e.dmg / 2, from: e) }
            onStoryEvent?("tremor")
        }
    }
    /// Below 40% health, third-generation lords and later speed up.
    func lordLeapPeriod(_ e: Enemy) -> Double {
        let base = Reign.leapPeriod(generation: e.generation)
        return e.generation >= 3 && e.hp * 5 < e.maxhp * 2 ? base * 0.6 : base
    }

    // MARK: outcomes

    func lordDefeated(_ e: Enemy) {
        guard let f = e.lordFloor, let i = reignIndex(f) else { return }
        floorLord = nil
        dropLoot(f, generation: e.generation, x: e.x, y: e.y)
        if e.isChallenger {
            let reward = defense.map { defenseReward($0, into: i) } ?? 0
            endDefense()
            reigns[i].generation += 1; reigns[i].defenses += 1
            siege = nil
            message(String(format: L("reign.defended"), floorName(f), reigns[i].defenses, reward))
            sfx(.craft); return
        }
        if e.generation == 1 { message(L("lord.\(f).last")) } else { message(lordCreed(reigns[i])) }
        for (id, n) in reigns[i].stolen { dropItem(id, n, e.x, e.y) }
        reigns[i].stolen = [:]
        reigns[i].state = .vacant; reigns[i].vacantT = Reign.vacantTime
        setThroneArt(f); sfx(.craft)
        message(String(format: L(meetsClaimCondition(f) ? "reign.beatenCanClaim" : "reign.beatenNeedLight"), floorName(f), L("floor.\(f).light")))
        if reigns[i].truthKnown != true { reigns[i].truthKnown = true; message(String(format: L("reign.truthUnlocked"), L("lord.\(f).name"))) }
    }

    private func dropLoot(_ floor: Int, generation g: Int, x: Double, y: Double) {
        let items = Reign.tributeItems(floor)
        for id in items.prefix(2) { dropItem(id, 2 + g, x, y) }
        dropItem(Item.potion, 1 + g / 2, x, y)
        if g >= 3 { dropItem(items[2], 1 + g / 3, x, y) }
    }

    /// The player was beaten or absent: the challenger takes the throne and everything stored there.
    func loseThrone(_ floor: Int) {
        guard let i = reignIndex(floor), reigns[i].state == .player else { return }
        let loot = reigns[i].tribute
        endDefense()
        if let e = floorLord, e.lordFloor == floor { enemies.removeAll { $0 === e }; floorLord = nil; if boss === e { boss = nil } }
        crownNewLord(i, stolen: loot)
        siege = nil
        sfx(.roar); onStoryEvent?("tremor")
        message(String(format: L("reign.lost"), floorName(floor), lordName(reigns[i])))
    }

    /// Dying in a battle wounds the throne; the player returns beside it.
    func playerDied() {
        if let d = defense { d.throneHP -= d.throneMax * 0.2; message(L("defense.fell")) }
    }

    func touchThrone(_ x: Int, _ y: Int) {
        guard let i = reigns.firstIndex(where: { let t = Reign.thronePosition($0.floor, worldWidth: world.w); return t.x == x && t.y == y }) else { return }
        let f = reigns[i].floor
        switch reigns[i].state {
        case .lord: tip(String(format: L("reign.occupied"), lordName(reigns[i])))
        case .vacant:
            if !meetsClaimCondition(f) { tip(String(format: L("reign.needLight"), L("floor.\(f).light"))); return }
            reigns[i].state = .player; reigns[i].tribute = [:]; reigns[i].tributeT = 0; reigns[i].defenses = 0
            setThroneArt(f); sfx(.craft); onStoryEvent?("tremor")
            message(String(format: L("reign.claimed"), reigns[i].generation, floorName(f)))
            message(L("reign.claimNames"))
        case .player:
            if reigns[i].tribute.isEmpty { tip(L("reign.noTribute")); return }
            var total = 0
            for (id, n) in reigns[i].tribute { addItem(id, n); total += n }
            reigns[i].tribute = [:]; sfx(.open)
            message(String(format: L("reign.collected"), total))
        }
    }

    var throneHintText: String? {
        let ax = Int(floor(aimX)), ay = Int(floor(aimY))
        guard world.get(ax, ay) == Tile.throne,
              let r = reigns.first(where: { let t = Reign.thronePosition($0.floor, worldWidth: world.w); return t.x == ax && t.y == ay }) else { return nil }
        switch r.state {
        case .lord: return nil
        case .vacant: return L("hint.claim")
        case .player: return L("hint.collect")
        }
    }

    /// Objective panel once the descent is over.
    var reignObjective: (title: String, detail: String)? {
        if let d = defense {
            let hp = "\(max(0, Int(d.throneHP)))/\(Int(d.throneMax))"
            let title: String
            if d.bossStarted { title = String(format: L("objective.defenseBoss"), hp) }
            else if d.wave == 0 { title = String(format: L("objective.defensePrep"), Int(d.gapT), hp) }
            else { title = String(format: L("objective.defenseWave"), d.wave, d.waves, hp) }
            return (title, String(format: L("objective.defensePoints"), d.level, d.points, d.turrets.count, DefenseDesign.maxTurrets))
        }
        if let s = siege {
            let t = Reign.thronePosition(s.floor, worldWidth: world.w)
            return (String(format: L("objective.siege"), floorName(s.floor), Int(s.timeLeft)), directionText(to: t))
        }
        guard let i = reignIndex(currentFloor) else { return nil }
        let r = reigns[i], t = Reign.thronePosition(r.floor, worldWidth: world.w)
        switch r.state {
        case .lord: return (lordName(r), directionText(to: t))
        case .vacant: return (String(format: L("objective.vacant"), Int(r.vacantT)), meetsClaimCondition(r.floor) ? directionText(to: t) : String(format: L("reign.needLight"), L("floor.\(r.floor).light")))
        case .player: return (String(format: L("objective.ruling"), floorName(r.floor)), String(format: L("objective.tribute"), r.tribute.values.reduce(0, +)))
        }
    }

    private func directionText(to t: (x: Int, y: Int)) -> String {
        let dx = t.x - Int(player.x), dy = t.y - Int(player.y)
        let h = dx == 0 ? "" : String(format: L(dx > 0 ? "dir.right" : "dir.left"), abs(dx))
        let v = abs(dy) < 3 ? "" : String(format: L(dy > 0 ? "dir.down" : "dir.up"), abs(dy))
        if h.isEmpty && v.isEmpty { return L("objective.throneHere") }
        return String(format: L("objective.throneAt"), [h, v].filter { !$0.isEmpty }.joined(separator: " "))
    }
}
