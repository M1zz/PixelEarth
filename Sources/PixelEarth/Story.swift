import Foundation

/// Acts, triggers, the camp, the core and the ending — all rule-level, no SpriteKit.
extension Game {

    static let fragments: [Int: String] = [
        4: "4층 · 소문의 길 — 벽마다 누가 무엇을 했다는 낙서가 가득하다. 누가 쓴 것인지는 아무도 모른다.",
        5: "5층 · 내일의 숲 — 새싹뿐인 숲. 어디선가 서랍 여닫는 소리가 난다. 여기라면 살 수 있다.",
        6: "6층 · 쉬지 않는 굴 — 곡괭이 소리가 한 번도 멈추지 않는다. 돌 속에서 무언가 비친다. 붉은 빛이 있다면 보일 것이다.",
        7: "7층 · 물벽의 집 — 물이 벽처럼 서 있다. 벽 너머에서 찻잔 부딪는 소리가 난다.",
        8: "8층 · 눈 감은 어둠 — 횃불이 죽는다. 살아 있는 빛만이 여기서 숨 쉰다.",
        9: "9층 · 하늘 창고 — 하늘이 여기 갇혀 있다. 어디선가 장부 넘기는 소리가 들린다.",
    ]

    func updateStory(_ dt: Double) {
        storyT += dt
        skyFactor += (skyTarget - skyFactor) * min(1, dt * 0.15)
        let p = player
        let py = Int(floor(p.y)), px = Int(floor(p.x))
        // Act 1: a quiet afternoon, then the sky is pulled underground
        if act == 1 {
            if !disasterStruck && updateTutorial(dt) {
                disasterStruck = true; skyTarget = 0.22
                world.openShaft()
                for t in world.shaftTiles { onTileChanged?(t.x, t.y) }
                for _ in 0..<60 { particles.append(Particle(x: Double(world.shaftX) + Double.random(in: -2...2), y: Double(world.surfaceAt(world.shaftX)) - Double.random(in: 0...4), vx: Double.random(in: -4...4), vy: Double.random(in: -9 ... -2), t: 1.2, life: 1.2, color: RGB(r: 120, g: 100, b: 90))) }
                sfx(.roar); onStoryEvent?("disaster")
                message("빛안개가 거꾸로 땅속으로 빨려 들어간다 — 발밑이 갈라졌다. 내려가야 한다.")
            }
            if disasterStruck && py > Layers.bandTop + 3 {
                act = 2
                world.collapseShaft()
                for t in world.shaftTiles { onTileChanged?(t.x, t.y) }
                for x in (world.shaftX - 4)...(world.shaftX + 4) { onTileChanged?(x, Layers.bandTop) }
                sfx(.roar); onStoryEvent?("collapse")
                message("뒤에서 통로가 무너졌다. 올라갈 길은… 아래에 있을 것이다.")
            }
        }
        // layer titles and fragments (once each)
        let li = Layers.index(forY: py)
        if li >= 4 && !layersSeen.contains(li) {
            layersSeen.insert(li)
            if let f = Game.fragments[li] { message(f) }
            if Reign.floors.contains(li) { message(L("lord.\(li).rumor")) }
            if li == 8 && !jar.hasAnySpore { tip("여기선 횃불이 꺼진다. 병에 포자를 심어 빛을 키워야 한다.") }
        }
        // Act 3: the sky returns as you climb
        if act == 3 {
            let top = Double(world.surfaceAt(px)), band = Double(Layers.bandTop)
            let prog = max(0, min(1, (band - p.y) / max(1, band - top)))
            if prog > ascent { ascent = prog; skyTarget = 0.22 + 0.78 * ascent }
            if py <= world.surfaceAt(px) && ascent >= 0.95 {
                act = 5; skyTarget = 1
                onStoryEvent?("sky")
                message("하늘.")
                for _ in 0..<80 { particles.append(Particle(x: p.x + Double.random(in: -12...12), y: p.y - Double.random(in: 0...10), vx: Double.random(in: -1...1), vy: Double.random(in: -3 ... -1), t: 3, life: 3, color: RGB(r: 255, g: 240, b: 200), snow: true)) }
            }
        }
    }

    // MARK: jar

    /// Put the held stack's top item into the jar (F key / jar panel).
    func feedJar(slot i: Int) {
        guard var s = player.inv[i] else { tip("손에 든 것이 없습니다"); return }
        if let why = jar.acceptReason(s.id) { tip(why); return }
        let what = jar.feed(s.id)
        s.n -= 1; player.inv[i] = s.n <= 0 ? nil : s
        onInventoryChanged?(); sfx(.heal)
        message("\(itemName(s.id)) → \(jar.named): \(what) (\(jar.colorName))")
        if jar.stage == 1 && jar.score == 11 { message("병이 등불만큼 자랐다.") }
        if jar.isWhite { tip("흰빛이다 — 모든 것이 보이지만, 모든 것이 당신을 본다.") }
    }

    // MARK: camp pedestals

    func pedestalHint(_ x: Int, _ y: Int) -> String {
        let st = world.pedestalState["\(x),\(y)"] ?? 0
        if st > 0 { return ["", "붉은 빛풀이 자라고 있다 — 대장간이 깨어났다", "초록 빛풀이 자라고 있다 — 온실이 깨어났다", "푸른 빛풀이 자라고 있다 — 우물이 깨어났다"][st] }
        let want = pedestalWants(x)
        return "제단 — \(["", "붉은", "초록", "푸른"][want]) 빛풀을 들고 L (포자 2 + 흙 2로 제작)"
    }
    func pedestalWants(_ x: Int) -> Int { x < world.campX ? 1 : (x == world.campX ? 2 : 3) }

    func plantOnPedestal(_ x: Int, _ y: Int) -> Bool {
        guard let s = player.held else { tip(pedestalHint(x, y)); return false }
        let want = pedestalWants(x)
        let plant = [0, Tile.redPlant, Tile.greenPlant, Tile.bluePlant][want]
        guard s.id == plant else { tip(pedestalHint(x, y)); return false }
        let key = "\(x),\(y)"
        if (world.pedestalState[key] ?? 0) > 0 { tip("이미 빛이 자라고 있다"); return false }
        removeItem(plant, 1)
        world.pedestalState[key] = want
        onTileChanged?(x, y)
        // the light spreads: plants on the floor around the pedestal
        for dx in [-3, -2, 2, 3] { let px = x + dx; if world.get(px, y) == Tile.air && world.solid(px, y + 1) { setTile(px, y, plant) } }
        sfx(.craft)
        let lit = world.pedestals.filter { (world.pedestalState["\($0.x),\($0.y)"] ?? 0) > 0 }.count
        message(["", "대장간이 깨어났다 — 누군가 돌아왔다.", "온실이 깨어났다 — 누군가 돌아왔다.", "우물이 깨어났다 — 누군가 돌아왔다."][want])
        if lit == 3 { message("캠프가 모두 깨어났다. 이제 아래로, 끝까지."); onStoryEvent?("camp") }
        return true
    }

    var campLit: Int { world.pedestals.filter { (world.pedestalState["\($0.x),\($0.y)"] ?? 0) > 0 }.count }

    // MARK: core & ending

    func touchCore() {
        if act >= 3 { tip(act == 4 ? "빛은 여기 남았다." : "빛은 이미 위로 돌아가고 있다."); return }
        if !jar.isWhite { tip("심장이 반응하지 않는다. 흰빛이 필요하다 — 붉은·초록·푸른 빛을 모두 병에."); return }
        if campLit < 3 { tip("심장이 떨린다… 하지만 위에서 기다리는 이들이 아직 어둠 속이다. 캠프의 제단 세 개를 먼저 밝혀라."); return }
        pendingChoice = true
        onStoryEvent?("choice")
    }

    func chooseEnding(up: Bool) {
        pendingChoice = false
        if up {
            act = 3
            message("창고 문이 열리고 빛이 위로 흐르기 시작한다. 무너진 암석이 부서질 것이다 — 올라가라.")
            // the stratum loosens: mark chunks dirty so autotile edges re-bake as it changes state
            for x in stride(from: 0, to: world.w, by: 8) { onTileChanged?(x, Layers.bandTop) }
            sfx(.craft)
            if reignIndex(9).map({ reigns[$0].truthKnown == true }) ?? false { message(L("ending.lord.up")) }
        } else {
            act = 4
            message("빛은 여기 남는다. 하늘은 이제 당신의 것이다. 창고 안은 여전히 조용하다.")
            for p in world.pedestals { for dx in [-1, 1] where world.get(p.x + dx, p.y) == Tile.air { setTile(p.x + dx, p.y, Tile.greenPlant) } }
            sfx(.heal)
            if reignIndex(9).map({ reigns[$0].truthKnown == true }) ?? false { message(L("ending.lord.stay")) }
        }
        onStoryEvent?(up ? "up" : "stay")
    }
}
