import Foundation

/// The first afternoon: guided steps, then free time on the surface, then the disaster. Rule-level, no SpriteKit.
enum Tutorial {
    static let look = 0, walk = 1, jump = 2, chop = 3, planks = 4, bench = 5, sword = 6, slime = 7, feed = 8, done = 9
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
    private var plankWorth: Int { countItem(Tile.wood) * 4 + countItem(Tile.plank) }

    func startTutorial() {
        tutorialStep = Tutorial.look; tutorialCalm = 0; tutorialWalked = 0; tutorialLastX = player.x; tutorialSlimeT = 0
        jarLooked = false; tremorStage = 0; freeChest = nil
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
        case Tutorial.walk: if tutorialWalked >= 6 { advanceTutorial() }
        case Tutorial.jump: if !player.ground && player.vy < 0 { advanceTutorial() }
        case Tutorial.chop: if plankWorth >= 16 || nearBench() { advanceTutorial() }
        case Tutorial.planks: if countItem(Tile.plank) >= 16 || nearBench() { advanceTutorial() }
        case Tutorial.bench: if nearBench() { advanceTutorial() }
        case Tutorial.sword: if countItem(Item.woodSword) > 0 { advanceTutorial() }
        case Tutorial.slime:
            if countItem(Item.gel) > 0 || jar.gel > 0 { advanceTutorial() } else { keepTutorialSlime(dt) }
        case Tutorial.feed:
            if jar.gel > 0 { advanceTutorial() } else if countItem(Item.gel) == 0 { keepTutorialSlime(dt) }
        case Tutorial.look: if jarLooked { advanceTutorial() }
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

    /// A slime nearby for the combat step, replaced if it wanders off or dies without dropping gel.
    private func keepTutorialSlime(_ dt: Double) {
        tutorialSlimeT -= dt
        guard tutorialSlimeT <= 0 else { return }
        tutorialSlimeT = 2
        if enemies.contains(where: { $0.type == .slime && abs($0.x - player.x) < 30 }) { return }
        let sx = max(3, min(world.w - 4, Int(player.x) + (player.face >= 0 ? 9 : -9)))
        enemies.append(Enemy(type: .slime, x: Double(sx) + 0.5, y: Double(world.surfaceAt(sx) - 2)))
    }

    /// Leaves a reward over the hill: a reason to walk around before the ground opens.
    private func hideFreeChest() {
        let dir = player.x > Double(world.shaftX) ? 1 : -1
        var x = max(4, min(world.w - 5, Int(player.x) + dir * 28))
        for _ in 0..<20 where world.get(x, world.surfaceAt(x) - 1) != Tile.air { x += dir }
        let y = world.surfaceAt(x) - 1
        guard world.get(x, y) == Tile.air else { return }
        world.chests["\(x),\(y)"] = [ItemStack(id: Tile.torch, n: 10), ItemStack(id: Item.potion, n: 2), ItemStack(id: Tile.wood, n: 12)]
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
        if tutorialStep == Tutorial.chop { detail += " (\(min(4, plankWorth / 4))/4)" }
        if tutorialStep == Tutorial.planks { detail += " (\(min(16, countItem(Tile.plank)))/16)" }
        return (String(format: L("objective.step"), tutorialStep + 1, Tutorial.done, L("step.\(tutorialStep).title")), detail)
    }
}
