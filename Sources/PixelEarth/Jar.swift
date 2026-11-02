import Foundation

/// The jar: the last living light. What goes in decides the color the player carries,
/// and the color decides what the world reveals. No decay, no death — only dormancy.
struct Jar: Codable {
    var water: Double = 0          // 0...10, from standing in underground water
    var iron = 0, gold = 0, diamond = 0   // minerals fed (0...5 each)
    var sporeR = false, sporeG = false, sporeB = false
    var gel = 0                    // small creatures (0...6)
    var moss: Double = 0           // grows while water > 3
    var named: String = "병"

    /// Light the jar emits, per channel 0...15.
    var light: RGB {
        let bonus = min(2, gel / 2)
        var r = 2 + (sporeR ? 6 : 0) + min(5, iron) + bonus
        var g = 2 + (sporeG ? 6 : 0) + min(5, gold) + bonus + Int(moss / 4)
        var b = 2 + (sporeB ? 6 : 0) + min(5, diamond) + bonus + Int(water / 3)
        r = min(15, r); g = min(15, g); b = min(15, b)
        return RGB(r: r, g: g, b: b)
    }
    var brightness: Int { let l = light; return max(l.r, l.g, l.b) }
    var score: Int { (sporeR ? 4 : 0) + (sporeG ? 4 : 0) + (sporeB ? 4 : 0) + iron + gold + diamond + gel + Int(water / 2) + Int(moss / 3) }
    /// 0 jar, 1 lantern, 2 greenhouse pack
    var stage: Int { score >= 22 ? 2 : (score >= 11 ? 1 : 0) }
    var stageName: String { ["유리병", "등불", "등에 메는 온실"][stage] }

    var isRed: Bool { light.r >= 9 }
    var isGreen: Bool { light.g >= 9 }
    var isBlue: Bool { light.b >= 9 }
    var isViolet: Bool { light.r >= 8 && light.b >= 8 }
    var isWhite: Bool { light.r >= 10 && light.g >= 10 && light.b >= 10 }

    var colorName: String {
        let l = light
        if isWhite { return "흰빛" }
        if isViolet { return "보랏빛" }
        if l.r >= 8 && l.g >= 8 { return "노란빛" }
        if l.g >= 8 && l.b >= 8 { return "청록빛" }
        if isRed { return "붉은빛" }
        if isGreen { return "초록빛" }
        if isBlue { return "푸른빛" }
        return "희미한 빛"
    }

    /// Can this item go in? Returns a short reason when it can't.
    func acceptReason(_ id: Int) -> String? {
        switch id {
        case Tile.iron: return iron >= 5 ? "철은 충분합니다" : nil
        case Tile.gold: return gold >= 5 ? "금은 충분합니다" : nil
        case Tile.diamondOre, Item.diamond: return diamond >= 5 ? "다이아는 충분합니다" : nil
        case Tile.redSpore: return sporeR ? "이미 붉은 포자가 자랍니다" : nil
        case Tile.greenSpore: return sporeG ? "이미 초록 포자가 자랍니다" : nil
        case Tile.blueSpore: return sporeB ? "이미 푸른 포자가 자랍니다" : nil
        case Item.gel: return gel >= 6 ? "벌레가 너무 많습니다" : nil
        default: return "병에 넣을 수 없는 것입니다"
        }
    }
    /// Apply one unit. Returns what changed, for the message.
    mutating func feed(_ id: Int) -> String {
        switch id {
        case Tile.iron: iron += 1; return "흙이 붉어집니다"
        case Tile.gold: gold += 1; return "흙에 금빛이 섞입니다"
        case Tile.diamondOre, Item.diamond: diamond += 1; return "흙이 푸르게 반짝입니다"
        case Tile.redSpore: sporeR = true; return "붉은 포자가 뿌리를 내렸습니다"
        case Tile.greenSpore: sporeG = true; return "초록 포자가 뿌리를 내렸습니다"
        case Tile.blueSpore: sporeB = true; return "푸른 포자가 뿌리를 내렸습니다"
        case Item.gel: gel += 1; return "작은 빛벌레가 늘었습니다"
        default: return ""
        }
    }
    mutating func tick(_ dt: Double, inWater: Bool) {
        if inWater && water < 10 { water = min(10, water + dt * 0.8) }
        if water > 3 && moss < 12 { moss += dt * 0.02 }
    }
    /// A plant item grown from the jar's spores (for pedestals / lighting layers).
    var hasAnySpore: Bool { sporeR || sporeG || sporeB }
}
