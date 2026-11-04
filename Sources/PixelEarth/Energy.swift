import Foundation

/// The jar's light is spent and earned: glowing, seeing through rock with the lens, digging and giving light away
/// all draw on it; springs, what is fed to the jar, the camp and light shards fill it. Empty, it barely glows.
extension Jar {
    var energyCap: Double { 100 + 50 * Double(stage) }
    var energy: Double {
        get { min(energyCap, energyStore ?? energyCap) }
        set { energyStore = max(0, min(energyCap, newValue)) }
    }
}

extension Game {
    static let glowDrain = 0.12, lensDrain = 0.6, campFill = 3.0
    static let houseCost = 10.0, springGain = 60.0, shardGain = 40.0

    var jarEmpty: Bool { jar.energy < 0.5 }

    func updateEnergy(_ dt: Double) {
        var drain = jarCovered ? 0 : Game.glowDrain
        if lensActive { drain += Game.lensDrain }
        jar.energy -= drain * dt
        // the woken camp keeps the jar topped up
        if world.pedestals.contains(where: { (world.pedestalState["\($0.x),\($0.y)"] ?? 0) > 0 && abs(Double($0.x) - player.x) < 14 && abs(Double($0.y) - player.y) < 8 }) {
            jar.energy += Game.campFill * dt
        }
        if jarEmpty && lensActive { lensActive = false; tip(L("energy.lensOff")) }
        let low = jar.energy < jar.energyCap * 0.2
        if low && !warnedLowEnergy { warnedLowEnergy = true; tip(L("energy.low")) }
        if !low { warnedLowEnergy = false }
    }

    /// What feeding an item gives back to the light.
    func energyFor(_ id: Int) -> Double {
        switch id {
        case Tile.redSpore, Tile.greenSpore, Tile.blueSpore: return 30
        case Tile.iron, Tile.gold, Item.diamond: return 15
        case Item.gel: return 10
        default: return 8
        }
    }

    func gainEnergy(_ n: Double) {
        let before = jar.energy
        jar.energy += n
        let got = Int((jar.energy - before).rounded())
        if got > 0 { floats.append(FloatText(x: player.x, y: player.y - 0.5, t: 1.2, text: String(format: L("energy.gain"), got), color: RGB(r: 240, g: 250, b: 200))) }
    }

    /// The tutorial houses and anything else that costs light: false (with a tip) if there is not enough.
    func spendEnergy(_ n: Double) -> Bool {
        guard jar.energy >= n else { tip(String(format: L("energy.notEnough"), Int(n))); return false }
        jar.energy -= n; return true
    }
}

extension Game {
    /// The long goal under the objective: the errand's houses, then how deep the descent has reached.
    var progressText: String? {
        if act == 1 && !disasterStruck { return tutorialStep < Tutorial.done ? String(format: L("progress.errand"), housesLit, World.houses.count) : nil }
        guard act == 2 || act == 1 else { return nil }
        let deepest = max(layersSeen.max() ?? 1, currentFloor)
        return String(format: L("progress.descent"), min(9, max(1, deepest)))
    }
}
