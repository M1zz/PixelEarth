import Foundation

/// One on-screen nudge: an action symbol, the key that does it, and what it does.
struct KeyHint: Equatable {
    var symbol: String          // SF Symbol name
    var key: String             // keycap text
    var text: String
    var urgent = false          // gold and pulsing: the player probably needs this now
}

private enum HintSymbol {
    static let hold = "hand.raised", place = "square.stack.3d.up", mine = "hammer", attack = "bolt", use = "hand.tap"
    static let feed = "arrow.down.circle", drop = "trash", craft = "wrench.and.screwdriver", bag = "bag", jar = "sparkles"
    static let open = "shippingbox", move = "arrow.left.and.right", jump = "arrow.up", down = "arrow.down", close = "xmark", bow = "scope"
}

extension Game {
    private func hint(_ symbol: String, _ key: String, _ text: String, urgent: Bool = false) -> KeyHint {
        KeyHint(symbol: symbol, key: L(key), text: L(text), urgent: urgent)
    }
    private func slotKey(_ i: Int) -> String { "\(i + 1)" }

    /// "Press this to hold that", or "open the bag" when it landed beyond the hotbar.
    private func holdHint(_ id: Int) -> KeyHint? {
        if player.held?.id == id { return nil }
        guard let i = player.inv.firstIndex(where: { $0?.id == id }) else { return nil }
        if i < Game.handSlots { return KeyHint(symbol: HintSymbol.hold, key: slotKey(i), text: String(format: L("hint.holdItem"), itemName(id)), urgent: true) }
        return KeyHint(symbol: HintSymbol.bag, key: "I", text: String(format: L("hint.findInBag"), itemName(id)), urgent: true)
    }

    private func tutorialHints() -> [KeyHint] {
        guard act == 1, !disasterStruck else { return [] }
        switch tutorialStep {
        case Tutorial.look: return [hint(HintSymbol.jar, "J", "hint.jar", urgent: true)]
        case Tutorial.houseA, Tutorial.houseB, Tutorial.houseC:
            return [hint(HintSymbol.move, "key.ad", "hint.move", urgent: true), hint(HintSymbol.jump, "key.space", "hint.jump"), hint(HintSymbol.use, "key.lmb", "hint.giveLight")]
        case Tutorial.box: return [KeyHint(symbol: "eye", key: "Tab", text: L("hint.lensHidden"), urgent: !(lensActive && lens == .hidden)), hint(HintSymbol.mine, "key.lmb", "hint.mineHold")]
        case Tutorial.feed:
            return [player.held?.id == Tile.greenSpore ? hint(HintSymbol.feed, "F", "hint.feed", urgent: true) : holdHint(Tile.greenSpore)].compactMap { $0 }
        case Tutorial.cover: return [hint(HintSymbol.jar, "C", jarCovered ? "hint.uncover" : "hint.cover", urgent: true)]
        default: return []
        }
    }

    /// Something that hunts by light is near: hiding the jar is an option. Once hidden, how to bring it back.
    private func coverHints() -> [KeyHint] {
        if jarCovered { return [hint(HintSymbol.jar, "C", "hint.uncover")] }
        let near = enemies.contains { $0.lordFloor == nil && $0.attackerCost == 0 && hypot($0.x - player.x, $0.y - player.y) < 12 }
        return near ? [hint(HintSymbol.jar, "C", "hint.cover")] : []
    }

    /// What can be done with whatever is under the cursor.
    private func targetHints() -> [KeyHint] {
        let wx = aimX, wy = aimY
        let tx = Int(floor(wx)), ty = Int(floor(wy))
        guard reach(tx, ty) else { return [] }
        if enemies.contains(where: { abs($0.x - wx) < $0.w / 2 + 0.7 && wy > $0.y - 0.6 && wy < $0.y + $0.h + 0.6 }) {
            return [hint(HintSymbol.attack, "key.lmb", "hint.attack")]
        }
        let t = world.get(tx, ty)
        if t == Tile.chest { return [hint(HintSymbol.open, "key.lmb", "hint.openChest")] }
        if t == Tile.throne {
            if let text = throneHintText { return [KeyHint(symbol: "crown", key: L("key.lmb"), text: text, urgent: true)] }
            return [hint(HintSymbol.use, "key.lmb", "hint.inspect")]
        }
        if t == Tile.core { return [hint(HintSymbol.use, "key.lmb", "hint.touchCore")] }
        if t == Tile.lightSpring { return [KeyHint(symbol: "sun.max", key: L("key.lmb"), text: L("hint.spring"), urgent: true)] }
        if t == Tile.pedestal {
            let want = [0, Tile.redPlant, Tile.greenPlant, Tile.bluePlant][pedestalWants(tx)]
            if (world.pedestalState["\(tx),\(ty)"] ?? 0) == 0 && player.held?.id == want { return [hint(HintSymbol.place, "key.rmb", "hint.plant")] }
            return [hint(HintSymbol.use, "key.lmb", "hint.inspect")]
        }
        if t != Tile.air && !TILES[t].liquid && tileTier(t) <= heldStats().tier { return [hint(HintSymbol.mine, "key.lmb", "hint.mineHold")] }
        return []
    }

    private func heldHints() -> [KeyHint] {
        guard let s = player.held else { return [] }
        var out: [KeyHint] = []
        if s.id < 100, TILES[s.id].placeable { out.append(hint(HintSymbol.place, "key.rmb", "hint.place")) }
        if let it = ITEMS[s.id] {
            if it.use != nil { out.append(hint(HintSymbol.use, "key.lmb", "hint.use")) }
            if it.tool == .bow { out.append(hint(HintSymbol.bow, "key.lmb", "hint.shoot")) }
        }
        if jar.acceptReason(s.id) == nil { out.append(hint(HintSymbol.feed, "F", "hint.feed")) }
        out.append(hint(HintSymbol.drop, "Q", "hint.drop"))
        return out
    }

    private func movementHints() -> [KeyHint] {
        let x = Int(floor(player.x)), feet = Int(floor(player.y + player.h + 0.05))
        let vine = world.get(x, Int(floor(player.y + 0.8))) == Tile.vine || world.get(x, Int(floor(player.y + 1.5))) == Tile.vine
        if vine { return [hint(HintSymbol.jump, "key.ws", "hint.climb")] }
        if world.get(x, feet) == Tile.platform { return [hint(HintSymbol.down, "S", "hint.dropDown")] }
        return []
    }

    /// The hints for this frame, most useful first.
    func keyHints(panel: PanelKind?, modal: Bool = false) -> [KeyHint] {
        let nav = hint(HintSymbol.move, "key.wasd", "hint.navigate")
        if modal { return [nav, hint(HintSymbol.use, "key.lmb", "hint.select")] }
        switch panel {
        case .inventory: return [nav, hint(HintSymbol.use, "key.lmb", "hint.bagClick"), hint(HintSymbol.close, "ESC", "hint.close")]
        case .craft: return [nav, hint(HintSymbol.craft, "key.lmb", "hint.craftClick"), hint(HintSymbol.close, "ESC", "hint.close")]
        case .jar: return [nav, hint(HintSymbol.feed, "F", "hint.feed"), hint(HintSymbol.close, "ESC", "hint.close")]
        case .reign, .lore: return [nav, hint(HintSymbol.use, "K", "hint.select"), hint(HintSymbol.close, "ESC", "hint.close")]
        case nil: break
        }
        var out = tutorialHints()
        if nearbyJunction() != nil { out.insert(KeyHint(symbol: "arrow.turn.up.right", key: L("key.lmb"), text: L("hint.turn"), urgent: true), at: 0) }
        if let d = defense {
            out.append(KeyHint(symbol: "scope", key: "B", text: String(format: L("hint.turret"), DefenseDesign.turretCost), urgent: d.wave == 0))
            out.append(KeyHint(symbol: "square.stack.3d.up", key: "V", text: String(format: L("hint.wall"), DefenseDesign.wallCost), urgent: d.wave == 0))
        }
        if newItemT > 0, let id = newItemId, let h = holdHint(id) { out.append(h) }
        if !craftOpened, RECIPES.contains(where: { !$0.bench && canCraft($0, bench: false) }) {
            out.append(hint(HintSymbol.craft, "E", "hint.craft", urgent: true))
        }
        out += coverHints() + movementHints() + targetHints() + heldHints()
        var seen: [KeyHint] = []
        for h in out where !seen.contains(where: { $0.key == h.key && $0.text == h.text }) { seen.append(h) }
        return Array(seen.prefix(5))
    }
}
