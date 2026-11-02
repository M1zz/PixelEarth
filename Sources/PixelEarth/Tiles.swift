import Foundation

// MARK: - Tiles

enum Tile {
    static let air = 0, dirt = 1, grass = 2, stone = 3, wood = 4, leaves = 5, coal = 6, iron = 7, gold = 8, sand = 9
    static let torch = 10, plank = 11, bedrock = 12, brick = 13, bench = 14, glass = 15, door = 16, water = 17, snow = 18
    static let ice = 19, cactus = 20, shroom = 21, lava = 22, chest = 23, diamondOre = 24, flower = 25, platform = 26
    static let pine = 27, snowleaf = 28, lantern = 29, stonewall = 30
    // Act / light-gate tiles
    static let rubble = 31, crystal = 32, redSpore = 33, blueSpore = 34, greenSpore = 35
    static let hiddenVein = 36, ghostStone = 37, tideWall = 38, pedestal = 39, core = 40
    static let redPlant = 41, greenPlant = 42, bluePlant = 43, vine = 44, throne = 45, junction = 46
    static let count = 47
}

/// Vertical structure of the world (tile rows). Surface is around row 95; the camp crevice is "layer 5".
enum Layers {
    static let bandTop = 148      // collapsed stratum (rubble band) rows bandTop..<bandTop+3
    static let campTop = 152, campBottom = 172
    static let redTop = 176, blueTop = 206, darkTop = 236, cityTop = 262
    static func name(forY y: Int) -> String? {
        if y < bandTop - 40 { return nil }
        if y < bandTop { return "4층 · 무너진 옛 통로" }
        if y < redTop { return "5층 · 균열의 숲" }
        if y < blueTop { return "6층 · 붉은 가장자리" }
        if y < darkTop { return "7층 · 물의 층" }
        if y < cityTop { return "8층 · 불이 꺼지는 어둠" }
        return "9층 · 빛의 도시"
    }
    static func index(forY y: Int) -> Int {
        if y < bandTop { return max(1, 4 - (bandTop - y) / 14) }
        if y < redTop { return 5 }
        if y < blueTop { return 6 }
        if y < darkTop { return 7 }
        if y < cityTop { return 8 }
        return 9
    }
}

struct RGB { var r: Int; var g: Int; var b: Int }

struct TileDef {
    var name: String
    var solid: Bool = false
    var hardness: Double = 1
    var tier: Int = 0
    /// Item dropped when broken. nil = drops itself, -1 = drops nothing.
    var drop: Int? = nil
    var light: RGB? = nil
    var liquid: Bool = false
    var platform: Bool = false
    var falls: Bool = false
    var autotile: Bool = false
    var frames: Int = 1
    var dust: RGB = RGB(r: 140, g: 110, b: 80)
    var placeable: Bool = true
    /// Light-gated tiles: `disguise` is what the tile looks like until the right light reaches it.
    var disguise: Int? = nil
    var climbable: Bool = false
}

let TILES: [TileDef] = {
    var t = [TileDef](repeating: TileDef(name: "?"), count: Tile.count)
    t[Tile.air] = TileDef(name: "공기", placeable: false)
    t[Tile.dirt] = TileDef(name: "흙", solid: true, hardness: 0.8, autotile: true, dust: RGB(r: 138, g: 90, b: 47))
    t[Tile.grass] = TileDef(name: "잔디", solid: true, hardness: 0.8, drop: Tile.dirt, autotile: true, dust: RGB(r: 69, g: 173, b: 60))
    t[Tile.stone] = TileDef(name: "돌", solid: true, hardness: 2.0, tier: 1, autotile: true, dust: RGB(r: 115, g: 120, b: 136))
    t[Tile.wood] = TileDef(name: "원목", solid: true, hardness: 1.5, autotile: true, dust: RGB(r: 135, g: 90, b: 52))
    t[Tile.leaves] = TileDef(name: "나뭇잎", hardness: 0.3, drop: -1, autotile: true, dust: RGB(r: 53, g: 144, b: 67))
    t[Tile.coal] = TileDef(name: "석탄", solid: true, hardness: 2.4, tier: 1, autotile: true, dust: RGB(r: 46, g: 46, b: 58))
    t[Tile.iron] = TileDef(name: "철광석", solid: true, hardness: 3.0, tier: 1, autotile: true, dust: RGB(r: 196, g: 138, b: 94))
    t[Tile.gold] = TileDef(name: "금광석", solid: true, hardness: 3.6, tier: 2, autotile: true, dust: RGB(r: 242, g: 187, b: 43))
    t[Tile.sand] = TileDef(name: "모래", solid: true, hardness: 0.7, falls: true, autotile: true, dust: RGB(r: 226, g: 205, b: 130))
    t[Tile.torch] = TileDef(name: "횃불", hardness: 0.1, light: RGB(r: 14, g: 10, b: 5), frames: 4, dust: RGB(r: 255, g: 180, b: 60))
    t[Tile.plank] = TileDef(name: "판자", solid: true, hardness: 1.1, autotile: true, dust: RGB(r: 196, g: 141, b: 75))
    t[Tile.bedrock] = TileDef(name: "기반암", solid: true, hardness: 1e9, tier: 9, autotile: true, dust: RGB(r: 38, g: 38, b: 46), placeable: false)
    t[Tile.brick] = TileDef(name: "돌벽돌", solid: true, hardness: 2.2, tier: 1, autotile: true, dust: RGB(r: 133, g: 139, b: 158))
    t[Tile.bench] = TileDef(name: "작업대", solid: true, hardness: 1.1, dust: RGB(r: 166, g: 124, b: 74))
    t[Tile.glass] = TileDef(name: "유리", solid: true, hardness: 0.4, autotile: true, dust: RGB(r: 200, g: 235, b: 255))
    t[Tile.door] = TileDef(name: "문", hardness: 1.0, frames: 2, dust: RGB(r: 140, g: 103, b: 68))
    t[Tile.water] = TileDef(name: "물", hardness: 1e9, tier: 9, liquid: true, frames: 4, dust: RGB(r: 59, g: 130, b: 232), placeable: false)
    t[Tile.snow] = TileDef(name: "눈", solid: true, hardness: 0.7, autotile: true, dust: RGB(r: 238, g: 245, b: 255))
    t[Tile.ice] = TileDef(name: "얼음", solid: true, hardness: 1.2, autotile: true, dust: RGB(r: 149, g: 210, b: 239))
    t[Tile.cactus] = TileDef(name: "선인장", solid: true, hardness: 0.6, drop: -1, autotile: true, dust: RGB(r: 63, g: 154, b: 68))
    t[Tile.shroom] = TileDef(name: "빛버섯", hardness: 0.2, light: RGB(r: 5, g: 12, b: 14), frames: 2, dust: RGB(r: 95, g: 230, b: 255))
    t[Tile.lava] = TileDef(name: "용암", hardness: 1e9, tier: 9, light: RGB(r: 13, g: 7, b: 2), liquid: true, frames: 4, dust: RGB(r: 255, g: 160, b: 42), placeable: false)
    t[Tile.chest] = TileDef(name: "보물상자", hardness: 0.5, frames: 2, dust: RGB(r: 166, g: 124, b: 74))
    t[Tile.diamondOre] = TileDef(name: "다이아몬드 광석", solid: true, hardness: 4.5, tier: 3, drop: Item.diamond, autotile: true, dust: RGB(r: 127, g: 240, b: 255))
    t[Tile.flower] = TileDef(name: "꽃", hardness: 0.1, drop: -1, frames: 4, dust: RGB(r: 255, g: 107, b: 157))
    t[Tile.platform] = TileDef(name: "발판", hardness: 0.6, platform: true, frames: 4, dust: RGB(r: 196, g: 141, b: 75))
    t[Tile.pine] = TileDef(name: "소나무", solid: true, hardness: 1.5, drop: Tile.wood, autotile: true, dust: RGB(r: 94, g: 63, b: 44))
    t[Tile.snowleaf] = TileDef(name: "눈잎", hardness: 0.3, drop: -1, autotile: true, dust: RGB(r: 47, g: 125, b: 68))
    t[Tile.lantern] = TileDef(name: "등불", hardness: 0.3, light: RGB(r: 15, g: 13, b: 8), frames: 2, dust: RGB(r: 255, g: 224, b: 138))
    t[Tile.stonewall] = TileDef(name: "돌담", solid: true, hardness: 2.0, tier: 1, autotile: true, dust: RGB(r: 94, g: 97, b: 108))
    t[Tile.rubble] = TileDef(name: "붕괴 암석", solid: true, hardness: 2.6, tier: 9, drop: Tile.stone, autotile: true, dust: RGB(r: 90, g: 76, b: 88), placeable: false)
    t[Tile.crystal] = TileDef(name: "빛 수정", solid: true, hardness: 1e9, tier: 9, autotile: true, dust: RGB(r: 190, g: 234, b: 248), placeable: false)
    t[Tile.redSpore] = TileDef(name: "붉은 포자", hardness: 0.2, light: RGB(r: 6, g: 1, b: 1), frames: 2, dust: RGB(r: 255, g: 95, b: 122))
    t[Tile.blueSpore] = TileDef(name: "푸른 포자", hardness: 0.2, light: RGB(r: 1, g: 2, b: 6), frames: 2, dust: RGB(r: 127, g: 200, b: 255))
    t[Tile.greenSpore] = TileDef(name: "초록 포자", hardness: 0.2, light: RGB(r: 1, g: 6, b: 2), frames: 2, dust: RGB(r: 127, g: 232, b: 154))
    t[Tile.hiddenVein] = TileDef(name: "숨은 광맥", solid: true, hardness: 3.6, tier: 1, drop: Tile.stone, autotile: true, dust: RGB(r: 242, g: 187, b: 43), placeable: false, disguise: Tile.stone)
    t[Tile.ghostStone] = TileDef(name: "유령 돌", solid: true, hardness: 1e9, tier: 9, autotile: true, dust: RGB(r: 180, g: 140, b: 220), placeable: false, disguise: Tile.stone)
    t[Tile.tideWall] = TileDef(name: "물의 장막", solid: true, hardness: 1e9, tier: 9, frames: 4, dust: RGB(r: 59, g: 130, b: 232), placeable: false, disguise: Tile.water)
    t[Tile.pedestal] = TileDef(name: "제단", hardness: 1e9, tier: 9, frames: 4, dust: RGB(r: 133, g: 139, b: 158), placeable: false)
    t[Tile.core] = TileDef(name: "빛의 심장", hardness: 1e9, tier: 9, frames: 2, dust: RGB(r: 255, g: 242, b: 210), placeable: false)
    t[Tile.redPlant] = TileDef(name: "붉은 빛풀", hardness: 0.3, light: RGB(r: 15, g: 4, b: 5), frames: 2, dust: RGB(r: 255, g: 95, b: 122))
    t[Tile.greenPlant] = TileDef(name: "초록 빛풀", hardness: 0.3, light: RGB(r: 4, g: 15, b: 6), frames: 2, dust: RGB(r: 127, g: 232, b: 154))
    t[Tile.bluePlant] = TileDef(name: "푸른 빛풀", hardness: 0.3, light: RGB(r: 4, g: 6, b: 15), frames: 2, dust: RGB(r: 127, g: 200, b: 255))
    t[Tile.throne] = TileDef(name: "왕좌", hardness: 1e9, tier: 9, light: RGB(r: 9, g: 8, b: 5), frames: 3, dust: RGB(r: 240, g: 200, b: 90), placeable: false)
    t[Tile.junction] = TileDef(name: "갈림길", solid: true, hardness: 1e9, tier: 9, light: RGB(r: 3, g: 5, b: 8), frames: 2, dust: RGB(r: 120, g: 150, b: 190), placeable: false)
    t[Tile.vine] = TileDef(name: "덩굴", hardness: 0.2, frames: 2, dust: RGB(r: 69, g: 173, b: 60), climbable: true)
    return t
}()

// MARK: - Items (ids >= 100). Tile ids double as item ids.

enum ToolKind { case pick, sword, bow }
enum UseKind { case heal, armor, life }

enum Item {
    static let woodPick = 100, stonePick = 101, ironPick = 102, goldPick = 103, diamondPick = 104
    static let woodSword = 110, ironSword = 111, goldSword = 112, diamondSword = 113
    static let gel = 120, ironBar = 121, goldBar = 122, diamond = 123
    static let potion = 130, bow = 131, arrow = 132, crown = 133
    static let ironArmor = 140, goldArmor = 141, diamondArmor = 142
    static let lightShard = 150
}

struct ItemDef {
    var name: String
    var tool: ToolKind? = nil
    var tier: Int = 0
    var power: Double = 1
    var dmg: Int = 0
    var armor: Double = 0
    var use: UseKind? = nil
    var stackable: Bool { tool == nil && armor == 0 }
}

let ITEMS: [Int: ItemDef] = [
    Item.woodPick: ItemDef(name: "나무 곡괭이", tool: .pick, tier: 1, power: 1.6, dmg: 5),
    Item.stonePick: ItemDef(name: "돌 곡괭이", tool: .pick, tier: 2, power: 2.6, dmg: 7),
    Item.ironPick: ItemDef(name: "철 곡괭이", tool: .pick, tier: 3, power: 4.2, dmg: 9),
    Item.goldPick: ItemDef(name: "금 곡괭이", tool: .pick, tier: 3, power: 6.5, dmg: 10),
    Item.diamondPick: ItemDef(name: "다이아 곡괭이", tool: .pick, tier: 4, power: 9, dmg: 12),
    Item.woodSword: ItemDef(name: "나무 검", tool: .sword, dmg: 12),
    Item.ironSword: ItemDef(name: "철 검", tool: .sword, dmg: 22),
    Item.goldSword: ItemDef(name: "금 검", tool: .sword, dmg: 34),
    Item.diamondSword: ItemDef(name: "다이아 검", tool: .sword, dmg: 52),
    Item.gel: ItemDef(name: "젤"), Item.ironBar: ItemDef(name: "철 주괴"), Item.goldBar: ItemDef(name: "금 주괴"), Item.diamond: ItemDef(name: "다이아몬드"),
    Item.potion: ItemDef(name: "치유 물약", use: .heal),
    Item.bow: ItemDef(name: "활", tool: .bow, dmg: 16), Item.arrow: ItemDef(name: "화살"),
    Item.crown: ItemDef(name: "옛 왕관"),
    Item.ironArmor: ItemDef(name: "철 갑옷", armor: 0.2, use: .armor),
    Item.goldArmor: ItemDef(name: "금 갑옷", armor: 0.32, use: .armor),
    Item.diamondArmor: ItemDef(name: "다이아 갑옷", armor: 0.48, use: .armor),
    Item.lightShard: ItemDef(name: "빛 조각", use: .life),
]

func itemName(_ id: Int) -> String { id < 100 ? TILES[id].name : (ITEMS[id]?.name ?? "?") }
func itemStackable(_ id: Int) -> Bool { id < 100 ? true : (ITEMS[id]?.stackable ?? true) }

struct ItemStack: Codable, Equatable { var id: Int; var n: Int }

struct Recipe { let cat: String; let out: Int; let n: Int; let input: [(Int, Int)]; let bench: Bool }
let CRAFT_CATS = ["기본", "빛", "도구", "무기", "갑옷", "재료"]
let RECIPES: [Recipe] = [
    Recipe(cat: "기본", out: Tile.plank, n: 4, input: [(Tile.wood, 1)], bench: false),
    Recipe(cat: "기본", out: Tile.torch, n: 4, input: [(Tile.wood, 1), (Tile.coal, 1)], bench: false),
    Recipe(cat: "기본", out: Tile.bench, n: 1, input: [(Tile.plank, 6)], bench: false),
    Recipe(cat: "기본", out: Tile.platform, n: 4, input: [(Tile.plank, 2)], bench: false),
    Recipe(cat: "기본", out: Tile.door, n: 1, input: [(Tile.plank, 6)], bench: true),
    Recipe(cat: "기본", out: Tile.glass, n: 4, input: [(Tile.sand, 4), (Tile.coal, 1)], bench: false),
    Recipe(cat: "기본", out: Tile.brick, n: 4, input: [(Tile.stone, 4)], bench: false),
    Recipe(cat: "기본", out: Tile.stonewall, n: 4, input: [(Tile.stone, 2), (Tile.dirt, 2)], bench: false),
    Recipe(cat: "기본", out: Tile.lantern, n: 2, input: [(Tile.glass, 1), (Tile.torch, 2)], bench: true),
    Recipe(cat: "빛", out: Tile.vine, n: 6, input: [(Tile.greenSpore, 1), (Tile.wood, 2)], bench: false),
    Recipe(cat: "빛", out: Tile.redPlant, n: 1, input: [(Tile.redSpore, 2), (Tile.dirt, 2)], bench: false),
    Recipe(cat: "빛", out: Tile.greenPlant, n: 1, input: [(Tile.greenSpore, 2), (Tile.dirt, 2)], bench: false),
    Recipe(cat: "빛", out: Tile.bluePlant, n: 1, input: [(Tile.blueSpore, 2), (Tile.dirt, 2)], bench: false),
    Recipe(cat: "도구", out: Item.woodPick, n: 1, input: [(Tile.plank, 8)], bench: true),
    Recipe(cat: "도구", out: Item.stonePick, n: 1, input: [(Tile.stone, 10), (Tile.plank, 4)], bench: true),
    Recipe(cat: "도구", out: Item.ironPick, n: 1, input: [(Item.ironBar, 6), (Tile.plank, 4)], bench: true),
    Recipe(cat: "도구", out: Item.goldPick, n: 1, input: [(Item.goldBar, 6), (Tile.plank, 4)], bench: true),
    Recipe(cat: "도구", out: Item.diamondPick, n: 1, input: [(Item.diamond, 4), (Item.goldBar, 2), (Tile.plank, 4)], bench: true),
    Recipe(cat: "무기", out: Item.woodSword, n: 1, input: [(Tile.plank, 10)], bench: true),
    Recipe(cat: "무기", out: Item.ironSword, n: 1, input: [(Item.ironBar, 8), (Tile.plank, 3)], bench: true),
    Recipe(cat: "무기", out: Item.goldSword, n: 1, input: [(Item.goldBar, 8), (Tile.plank, 3)], bench: true),
    Recipe(cat: "무기", out: Item.diamondSword, n: 1, input: [(Item.diamond, 5), (Item.goldBar, 3), (Tile.plank, 3)], bench: true),
    Recipe(cat: "무기", out: Item.bow, n: 1, input: [(Tile.plank, 6), (Item.gel, 3)], bench: true),
    Recipe(cat: "무기", out: Item.arrow, n: 8, input: [(Tile.plank, 1), (Tile.stone, 1)], bench: false),
    Recipe(cat: "재료", out: Item.ironBar, n: 1, input: [(Tile.iron, 3), (Tile.coal, 1)], bench: true),
    Recipe(cat: "재료", out: Item.goldBar, n: 1, input: [(Tile.gold, 3), (Tile.coal, 2)], bench: true),
    Recipe(cat: "재료", out: Item.potion, n: 1, input: [(Item.gel, 3), (Tile.leaves, 5)], bench: false),
    Recipe(cat: "재료", out: Item.lightShard, n: 1, input: [(Item.diamond, 1), (Tile.crystal, 3)], bench: true),
    Recipe(cat: "갑옷", out: Item.ironArmor, n: 1, input: [(Item.ironBar, 12)], bench: true),
    Recipe(cat: "갑옷", out: Item.goldArmor, n: 1, input: [(Item.goldBar, 12)], bench: true),
    Recipe(cat: "갑옷", out: Item.diamondArmor, n: 1, input: [(Item.diamond, 8), (Item.goldBar, 4)], bench: true),
]
