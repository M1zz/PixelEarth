import Foundation

class Entity {
    var x: Double = 0, y: Double = 0       // top-center origin in tile units (y grows downward)
    var vx: Double = 0, vy: Double = 0
    var w: Double = 0.7, h: Double = 1.7
    var ground = false, inWater = false, inLava = false
    var fly = false, dropThrough = false
    var landedVy: Double = 0               // vertical speed at the moment of landing (fall damage)
}

enum EnemyType { case slime, cave, ice, zombie, bat, king }

final class Enemy: Entity {
    let type: EnemyType
    var hp: Int, maxhp: Int, dmg: Int
    var t: Double = Double.random(in: 0...2)
    var hurt: Double = 0
    var face: Double = 1
    var anim: Double = 0
    var boss: Bool { type == .king }
    // floor lords and challengers (see Reign.swift)
    var lordFloor: Int? = nil
    var isChallenger = false
    var generation = 1
    var drawScale = 1.0
    var summonT = 4.0
    var lure: (x: Int, y: Int)? = nil     // light-starved: the torch it is heading for
    var lureT = 0.0, eatT = 0.0
    var pleaded = false         // a founder's mid-fight line, said once
    var attackerCost = 0        // above 0: a defense-wave attacker that marches on the throne
    var dropsGel: Bool { type == .slime || type == .cave || type == .ice }
    let id = UUID()

    init(type: EnemyType, x: Double, y: Double) {
        self.type = type
        switch type {
        case .slime: maxhp = 18; dmg = 8
        case .cave: maxhp = 60; dmg = 18
        case .ice: maxhp = 30; dmg = 12
        case .zombie: maxhp = 48; dmg = 14
        case .bat: maxhp = 22; dmg = 10
        case .king: maxhp = 650; dmg = 30
        }
        hp = maxhp
        super.init()
        self.x = x; self.y = y
        switch type {
        case .slime: w = 1.4; h = 0.95
        case .cave: w = 1.5; h = 1.1
        case .ice: w = 1.4; h = 0.95
        case .zombie: w = 0.7; h = 1.7
        case .bat: w = 1.0; h = 0.6; fly = true
        case .king: w = 4.3; h = 3.4
        }
    }
}

final class Drop: Entity {
    var id: Int, n: Int
    var t: Double = 0
    let uid = UUID()
    init(id: Int, n: Int, x: Double, y: Double, vx: Double, vy: Double) {
        self.id = id; self.n = n
        super.init()
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; w = 0.5; h = 0.5
    }
}

struct Arrow { var x: Double; var y: Double; var vx: Double; var vy: Double; var t: Double; var dmg: Int; let uid = UUID() }
struct Particle { var x: Double; var y: Double; var vx: Double; var vy: Double; var t: Double; var life: Double; var color: RGB; var snow: Bool = false }
struct FloatText { var x: Double; var y: Double; var t: Double; var text: String; var color: RGB; let uid = UUID() }

final class Player: Entity {
    var hp = 100, maxhp = 100
    var face: Double = 1
    var swing: Double = 0
    var inv: [ItemStack?] = Array(repeating: nil, count: 40)
    var sel = 0
    var dead: Double = 0
    var iframe: Double = 0
    var regen: Double = 0
    var armor: Double = 0
    var armorId: Int? = nil
    var breath: Double = 10
    var anim: Double = 0
    var jumpLock = false

    override init() {
        super.init()
        w = 0.72; h = 1.78
    }
    var held: ItemStack? { inv[sel] }
}

// MARK: - Physics shared by every entity

func moveEntity(_ e: Entity, _ world: World, _ dt: Double) {
    if !e.fly { e.vy += 36 * dt; if e.vy > 30 { e.vy = 30 } }
    let hx = e.w / 2
    var nx = e.x + e.vx * dt
    let top = Int(floor(e.y + 0.01)), bot = Int(ceil(e.y + e.h)) - 1
    if e.vx > 0 {
        let tx = Int(floor(nx + hx)); var hit = false
        if bot >= top { for y in top...bot where world.solid(tx, y) { hit = true } }
        if hit { nx = Double(tx) - hx - 0.001; e.vx = 0 }
    } else if e.vx < 0 {
        let tx = Int(floor(nx - hx)); var hit = false
        if bot >= top { for y in top...bot where world.solid(tx, y) { hit = true } }
        if hit { nx = Double(tx) + 1 + hx + 0.001; e.vx = 0 }
    }
    e.x = nx
    var ny = e.y + e.vy * dt
    e.ground = false; e.landedVy = 0
    let l = Int(floor(e.x - hx + 0.02)), r = Int(floor(e.x + hx - 0.02))
    if e.vy > 0 {
        let ty = Int(floor(ny + e.h)); var hit = false
        for x in l...r {
            let t = world.get(x, ty)
            if world.solid(x, ty) || (TILES[t].platform && e.y + e.h <= Double(ty) + 0.05 && !e.dropThrough) { hit = true }
        }
        if hit { ny = Double(ty) - e.h - 0.001; e.landedVy = e.vy; e.vy = 0; e.ground = true }
    } else if e.vy < 0 {
        let ty = Int(floor(ny)); var hit = false
        for x in l...r where world.solid(x, ty) { hit = true }
        if hit { ny = Double(ty) + 1 + 0.001; e.vy = 0 }
    }
    e.y = ny
    let mid = world.get(Int(floor(e.x)), Int(floor(e.y + e.h * 0.5)))
    e.inWater = mid == Tile.water
    e.inLava = mid == Tile.lava || world.get(Int(floor(e.x)), Int(floor(e.y + e.h - 0.1))) == Tile.lava
    if e.inWater { e.vy *= 0.86; if e.vy > 4 { e.vy = 4 } }
}
