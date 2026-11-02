import Foundation

/// The first afternoon: guided steps, then free time on the surface, then the disaster. Rule-level, no SpriteKit.
enum Tutorial {
    /// The first five minutes are about the jar, not crafting: look, move, follow a light, feed it, hide it.
    static let look = 0, walk = 1, jump = 2, follow = 3, feed = 4, cover = 5, done = 6
    /// How long the surface stays peaceful after the last step.
    static let freeTime = 180.0
    /// Skipping keeps a short calm so the disaster does not land on the first frame.
    static let skipCalm = 20.0
    /// The disaster comes even if the steps are ignored, so the story can never stall.
    static let maxAfternoon = 600.0
    /// Afternoon stops here until the disaster: no nightfall during the quiet part of the story.
    static let latestTime = 0.6
}

extension Game {
    func startTutorial() {
        tutorialStep = Tutorial.look; tutorialCalm = 0; tutorialWalked = 0; tutorialLastX = player.x; tutorialSlimeT = 0
        jarLooked = false; tremorStage = 0; freeChest = nil; tutorialSpore = nil; tutorialCovered = false
        newItemId = nil; newItemT = 0; craftOpened = false
    }

    func skipTutorial() {
        guard act == 1, !disasterStruck, tutorialStep < Tutorial.done else { return }
        tutorialStep = Tutorial.done; tutorialCalm = Tutorial.skipCalm
    }

    /// True once the disaster may strike.
    func updateTutorial(_ dt: Double) -> Bool {
        worldTime = min(worldTime, Tutorial.latestTime)
        if player.y > Double(Layers.bandTop - 8) || storyT > Tutorial.maxAfternoon { return true }
        if tutorialStep >= Tutorial.done { return updateFreeTime(dt) }
        if tutorialStep == Tutorial.look { tutorialLastX = player.x }
        tutorialWalked += abs(player.x - tutorialLastX); tutorialLastX = player.x
        switch tutorialStep {
        case Tutorial.look: if jarLooked { advanceTutorial() }
        case Tutorial.walk: if tutorialWalked >= 6 { advanceTutorial() }
        case Tutorial.jump: if !player.ground && player.vy < 0 { advanceTutorial() }
        case Tutorial.follow:
            if countItem(Tile.greenSpore) > 0 || jar.sporeG { advanceTutorial() } else { keepTutorialSpore() }
        case Tutorial.feed: if jar.sporeG { advanceTutorial() }
        case Tutorial.cover:
            if jarCovered { tutorialCovered = true } else if tutorialCovered { advanceTutorial() }
        default: break
        }
        return false
    }

    private func advanceTutorial() {
        tutorialStep += 1; sfx(.pick)
        if tutorialStep >= Tutorial.done {
            tutorialCalm = Tutorial.freeTime
            message(L("tutorial.finished"))
            hideFreeChest()
        }
    }

    /// A green spore glowing a short walk away: the first thing the jar's light leads to.
    private func keepTutorialSpore() {
        if let t = tutorialSpore, world.get(t.x, t.y) == Tile.greenSpore { return }
        let dir = player.face >= 0 ? 1 : -1
        for d in [12, -12, 16, -16, 9, -9] {
            let x = max(4, min(world.w - 5, Int(player.x) + dir * d)), y = world.surfaceAt(x) - 1
            if world.get(x, y) == Tile.air && world.solid(x, y + 1) { setTile(x, y, Tile.greenSpore); tutorialSpore = (x, y); return }
        }
    }

    /// Leaves a reward over the hill: a reason to walk around before the ground opens.
    private func hideFreeChest() {
        let dir = player.x > Double(world.shaftX) ? 1 : -1
        var x = max(4, min(world.w - 5, Int(player.x) + dir * 28))
        for _ in 0..<20 where world.get(x, world.surfaceAt(x) - 1) != Tile.air { x += dir }
        let y = world.surfaceAt(x) - 1
        guard world.get(x, y) == Tile.air else { return }
        world.chests["\(x),\(y)"] = [ItemStack(id: Tile.greenPlant, n: 3), ItemStack(id: Item.potion, n: 2), ItemStack(id: Tile.wood, n: 12)]
        setTile(x, y, Tile.chest)
        freeChest = (x, y)
    }

    private func updateFreeTime(_ dt: Double) -> Bool {
        tutorialCalm -= dt
        if tutorialCalm < 40 && tremorStage == 0 {
            tremorStage = 1; sfx(.roar); onStoryEvent?("tremor"); message(L("tutorial.tremor1"))
        }
        if tutorialCalm < 12 && tremorStage == 1 {
            tremorStage = 2; skyTarget = 0.6; sfx(.roar); onStoryEvent?("tremor"); message(L("tutorial.tremor2"))
        }
        return tutorialCalm <= 0
    }

    /// Text for the objective panel: what to do now, then the keys. nil hides the panel.
    var objective: (title: String, detail: String)? {
        if act != 1 || (disasterStruck && (siege != nil || defense != nil)) { return reignObjective }
        if disasterStruck {
            let d = world.shaftX - Int(player.x)
            if abs(d) <= 2 { return (L("objective.descend"), L("objective.descend.here")) }
            return (L("objective.descend"), String(format: L(d > 0 ? "objective.descend.right" : "objective.descend.left"), abs(d)))
        }
        if tutorialStep >= Tutorial.done {
            if let c = freeChest, world.get(c.x, c.y) == Tile.chest {
                let d = c.x - Int(player.x)
                return (L("objective.free"), String(format: L(d > 0 ? "objective.chest.right" : "objective.chest.left"), abs(d)))
            }
            return (L("objective.free"), L("objective.free.detail"))
        }
        var detail = L("step.\(tutorialStep).detail")
        if tutorialStep == Tutorial.follow, let t = tutorialSpore {
            let d = t.x - Int(player.x)
            if abs(d) > 2 { detail += " · " + String(format: L(d > 0 ? "objective.follow.right" : "objective.follow.left"), abs(d)) }
        }
        return (String(format: L("objective.step"), tutorialStep + 1, Tutorial.done, L("step.\(tutorialStep).title")), detail)
    }
}
