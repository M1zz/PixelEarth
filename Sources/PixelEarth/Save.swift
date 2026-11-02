import Foundation

struct SaveData: Codable {
    var version = 1
    var seed: UInt32
    var tiles: Data
    var explored: Data
    var surface: [Int]
    var biome: Data
    var chests: [String: [ItemStack]]
    var px: Double, py: Double, hp: Int, maxhp: Int
    var inv: [ItemStack?]
    var sel: Int
    var armor: Double
    var armorId: Int?
    var spawnX: Double, spawnY: Double
    var worldTime: Double
    var day: Int
    var zoom: Int
    var sound: Bool
    // story
    var jar: Jar? = nil
    var act: Int? = nil
    var storyT: Double? = nil
    var disasterStruck: Bool? = nil
    var skyFactor: Double? = nil
    var layersSeen: [Int]? = nil
    var ascent: Double? = nil
    var pedestalState: [String: Int]? = nil
    var tutorialStep: Int? = nil
    var tutorialCalm: Double? = nil
    var tremorStage: Int? = nil
    var freeChestX: Int? = nil
    var freeChestY: Int? = nil
    var reigns: [FloorReign]? = nil
    var siege: Siege? = nil
    var nextSiegeT: Double? = nil
    var passagesSeen: [Int]? = nil
}

enum SaveStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PixelEarth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("world1.save")
    }
    static func exists() -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func save(_ g: Game, zoom: Int, sound: Bool) {
        let w = g.world, p = g.player
        let d = SaveData(seed: w.seed, tiles: Data(w.tiles), explored: Data(w.explored), surface: w.surface, biome: Data(w.biome), chests: w.chests,
                         px: p.x, py: p.y, hp: p.hp, maxhp: p.maxhp, inv: p.inv, sel: p.sel, armor: p.armor, armorId: p.armorId,
                         spawnX: g.spawnX, spawnY: g.spawnY, worldTime: g.worldTime, day: g.day, zoom: zoom, sound: sound,
                         jar: g.jar, act: g.act, storyT: g.storyT, disasterStruck: g.disasterStruck, skyFactor: g.skyFactor,
                         layersSeen: Array(g.layersSeen), ascent: g.ascent, pedestalState: w.pedestalState,
                         tutorialStep: g.tutorialStep, tutorialCalm: g.tutorialCalm, tremorStage: g.tremorStage, freeChestX: g.freeChest?.x, freeChestY: g.freeChest?.y, reigns: g.reigns, siege: g.siege, nextSiegeT: g.nextSiegeT, passagesSeen: Array(g.passagesSeen))
        do {
            try JSONEncoder().encode(d).write(to: url, options: .atomic)
        } catch { NSLog("save failed: \(error)") }
    }

    /// Returns true on success. Zoom/sound preferences are applied by the caller via `lastLoaded`.
    static var lastLoaded: SaveData? = nil
    static func load(into g: Game) -> Bool {
        guard let data = try? Data(contentsOf: url), let d = try? JSONDecoder().decode(SaveData.self, from: data) else { return false }
        let w = g.world
        guard d.tiles.count == w.tiles.count, d.surface.count == w.w else { return false }
        w.seed = d.seed; w.noise = Noise(seed: d.seed)
        w.tiles = [UInt8](d.tiles); w.explored = [UInt8](d.explored); w.surface = d.surface; w.biome = [UInt8](d.biome); w.chests = d.chests
        let p = g.player
        p.x = d.px; p.y = d.py; p.hp = d.hp; p.maxhp = d.maxhp; p.inv = d.inv; p.sel = d.sel; p.armor = d.armor; p.armorId = d.armorId
        while p.inv.count < 40 { p.inv.append(nil) }
        p.vx = 0; p.vy = 0; p.dead = 0; p.breath = 10
        g.spawnX = d.spawnX; g.spawnY = d.spawnY; g.worldTime = d.worldTime; g.day = d.day
        g.enemies = []; g.drops = []; g.arrows = []; g.floats = []; g.particles = []; g.boss = nil
        w.computeStoryRefs()
        w.ensureLairs(); w.ensureJunctions()
        g.passagesSeen = Set(d.passagesSeen ?? [])
        g.reigns = d.reigns ?? Game.freshReigns(); g.siege = d.siege; g.floorLord = nil; g.nextSiegeT = d.nextSiegeT ?? Double.random(in: Reign.siegeInterval)
        w.throneCol = [:]; for f in Reign.floors { g.setThroneArt(f) }
        g.jar = d.jar ?? Jar(); g.act = d.act ?? 2; g.storyT = d.storyT ?? 100; g.disasterStruck = d.disasterStruck ?? true
        g.skyFactor = d.skyFactor ?? 0.22; g.skyTarget = g.act >= 5 ? 1 : (g.act == 3 ? 0.22 + 0.78 * (d.ascent ?? 0) : (g.disasterStruck ? 0.22 : 1))
        g.layersSeen = Set(d.layersSeen ?? []); g.ascent = d.ascent ?? 0; w.pedestalState = d.pedestalState ?? [:]; g.pendingChoice = false
        g.tutorialStep = d.tutorialStep ?? Tutorial.done; g.tutorialCalm = d.tutorialCalm ?? 0; g.tremorStage = d.tremorStage ?? 2
        g.tutorialWalked = 0; g.tutorialLastX = p.x; g.tutorialSlimeT = 0; g.jarLooked = false
        if let x = d.freeChestX, let y = d.freeChestY { g.freeChest = (x, y) } else { g.freeChest = nil }
        g.loaded = true
        lastLoaded = d
        return true
    }
}
