import Foundation
import SpriteKit
import ImageIO
import AppKit
import AVFoundation

/// SwiftPM builds use the generated resource bundle; the Xcode app target ships resources in the app bundle.
#if SWIFT_PACKAGE
let gameBundle = Bundle.module
#else
let gameBundle = Bundle.main
#endif

/// Localized text from the String Catalog.
func L(_ key: String) -> String { textBundle.localizedString(forKey: key, value: key, table: nil) }

/// Chosen from the user's languages explicitly: the resource bundle's own preferredLocalizations can answer English on a Korean system.
private let textBundle: Bundle = {
    let pick = Bundle.preferredLocalizations(from: gameBundle.localizations, forPreferences: Locale.preferredLanguages).first
    return pick.flatMap { gameBundle.path(forResource: $0, ofType: "lproj") }.flatMap { Bundle(path: $0) } ?? gameBundle
}()

/// Loads the PNG spritesheets from the package bundle and slices them into textures.
final class Assets {
    static let shared = Assets()

    let tilesImage: CGImage
    let wallsImage: CGImage
    private var tileCache: [Int: CGImage] = [:]   // key = row * 64 + col
    private var wallCache: [Int: CGImage] = [:]

    let playerSheet: SKTexture, armTex: SKTexture
    let slimeSheet: SKTexture, zombieSheet: SKTexture, batSheet: SKTexture, kingSheet: SKTexture
    let itemsSheet: SKTexture
    let mountains0: SKTexture, mountains1: SKTexture, clouds: SKTexture, stars: SKTexture
    let panel: SKTexture, slot: SKTexture, slotSel: SKTexture, heart: SKTexture, heartEmpty: SKTexture, cursor: SKTexture, glow: SKTexture, pixel: SKTexture, vessel: SKTexture
    let bugSheet: SKTexture, coreSheet: SKTexture
    var bugFrames: [SKTexture] = [], coreFrames: [SKTexture] = []

    private var itemTexCache: [Int: SKTexture] = [:]
    var playerFrames: [[SKTexture]] = []   // [armorSet][pose]
    var armFrames: [SKTexture] = []        // [armorSet]
    var slimeFrames: [[SKTexture]] = []    // [color][frame]
    var zombieFrames: [SKTexture] = []
    var batFrames: [SKTexture] = []
    var kingFrames: [SKTexture] = []
    /// The first lord of each floor has a drawing of their own (5...9); later lords wear the keeper's.
    var lordFrames: [Int: [SKTexture]] = [:]
    var grandmaFrames: [SKTexture] = []      // 3 breathing, 1 waving
    var turretFrames: [SKTexture] = []
    var decor: [DecorKind: SKTexture] = [:]

    static func url(_ name: String, _ ext: String = "png") -> URL {
        if let u = gameBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return u }
        if let u = gameBundle.url(forResource: name, withExtension: ext) { return u }
        fatalError("Missing resource \(name).\(ext)")
    }
    static func cgImage(_ name: String) -> CGImage {
        let u = url(name)
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("Bad image \(name)") }
        return img
    }
    static func tex(_ name: String) -> SKTexture {
        let t = SKTexture(cgImage: cgImage(name)); t.filteringMode = .nearest; return t
    }
    /// Sub-texture from top-left pixel coordinates.
    static func sub(_ t: SKTexture, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> SKTexture {
        let W = t.size().width, H = t.size().height
        let r = CGRect(x: CGFloat(x) / W, y: 1 - CGFloat(y + h) / H, width: CGFloat(w) / W, height: CGFloat(h) / H)
        let s = SKTexture(rect: r, in: t); s.filteringMode = .nearest; return s
    }

    private init() {
        tilesImage = Assets.cgImage("tiles"); wallsImage = Assets.cgImage("walls")
        playerSheet = Assets.tex("player"); armTex = Assets.tex("arm")
        slimeSheet = Assets.tex("slimes"); zombieSheet = Assets.tex("zombie"); batSheet = Assets.tex("bat"); kingSheet = Assets.tex("king")
        itemsSheet = Assets.tex("items")
        mountains0 = Assets.tex("mountains0"); mountains1 = Assets.tex("mountains1"); clouds = Assets.tex("clouds"); stars = Assets.tex("stars")
        panel = Assets.tex("panel"); slot = Assets.tex("slot"); slotSel = Assets.tex("slot_sel"); heart = Assets.tex("heart"); heartEmpty = Assets.tex("heart_empty")
        cursor = Assets.tex("cursor"); glow = Assets.tex("glow"); pixel = Assets.tex("pixel"); vessel = Assets.tex("vessel")
        bugSheet = Assets.tex("bug"); coreSheet = Assets.tex("core")
        bugFrames = (0..<2).map { Assets.sub(bugSheet, $0 * 4, 0, 4, 4) }
        coreFrames = (0..<2).map { Assets.sub(coreSheet, $0 * 48, 0, 48, 48) }
        armFrames = (0..<4).map { Assets.sub(armTex, $0 * 6, 0, 6, 12) }
        for set in 0..<4 { playerFrames.append((0..<9).map { Assets.sub(playerSheet, $0 * 20, set * 32, 20, 32) }) }
        for c in 0..<3 { slimeFrames.append((0..<2).map { Assets.sub(slimeSheet, (c * 2 + $0) * 24, 0, 24, 16) }) }
        zombieFrames = (0..<6).map { Assets.sub(zombieSheet, $0 * 26, 0, 26, 28) }   // 4 walking, 2 swallowing a flame
        batFrames = (0..<2).map { Assets.sub(batSheet, $0 * 24, 0, 24, 14) }
        kingFrames = (0..<5).map { Assets.sub(kingSheet, $0 * 72, 0, 72, 66) }     // breathing idle
        for f in 5...9 { let t = Assets.tex("lord\(f)"); lordFrames[f] = (0..<5).map { Assets.sub(t, $0 * 72, 0, 72, 66) } }
        let gm = Assets.tex("grandma"); grandmaFrames = (0..<4).map { Assets.sub(gm, $0 * 20, 0, 20, 32) }
        let turret = Assets.tex("turret"); turretFrames = (0..<3).map { Assets.sub(turret, $0 * 16, 0, 16, 24) }
        let d = Assets.tex("decor")
        decor = [.namesA: Assets.sub(d, 0, 0, 48, 48), .namesB: Assets.sub(d, 48, 0, 48, 48), .scratch: Assets.sub(d, 96, 0, 48, 48),
                 .sky: Assets.sub(d, 144, 0, 64, 48), .herb: Assets.sub(d, 208, 0, 16, 48), .bed: Assets.tex("bed")]
    }

    /// Tile sprite from the atlas (row = tile id, col = mask*2+variant for autotiles, frame index otherwise).
    func tile(_ id: Int, col: Int) -> CGImage? {
        let key = id * 64 + col
        if let c = tileCache[key] { return c }
        let img = tilesImage.cropping(to: CGRect(x: col * 16, y: id * 16, width: 16, height: 16))
        tileCache[key] = img
        return img
    }
    func wall(kind: Int, variant: Int) -> CGImage? {
        let key = kind * 4 + variant
        if let c = wallCache[key] { return c }
        let img = wallsImage.cropping(to: CGRect(x: key * 16, y: 0, width: 16, height: 16))
        wallCache[key] = img
        return img
    }

    /// Inventory icon for any item id (tiles use their fully-exposed autotile or frame 0).
    func itemTexture(_ id: Int) -> SKTexture {
        if let t = itemTexCache[id] { return t }
        var tex: SKTexture
        if id < 100 {
            let col = TILES[id].autotile ? 15 * 2 : 0
            if let img = tile(id, col: col) { tex = SKTexture(cgImage: img) } else { tex = pixel }
        } else {
            let i = id - 100
            tex = Assets.sub(itemsSheet, (i % 16) * 16, (i / 16) * 16, 16, 16)
        }
        tex.filteringMode = .nearest
        itemTexCache[id] = tex
        return tex
    }
}

/// The background loop for each situation (Tools/gen_music.py). Game.musicMood picks one; Sound crossfades.
enum MusicMood: String, CaseIterable {
    case afternoon, lost, camp, deep, fight
    var volume: Float { self == .fight ? 0.42 : 0.35 }
    /// Seconds to fade in: a fight arrives quickly, a place settles in slowly.
    var fadeIn: TimeInterval { self == .fight ? 1.2 : 4 }
}

/// Tiny sound manager: short WAVs generated by the asset script, played through NSSound,
/// plus the background loops, which follow the same on/off switch.
final class Sound {
    static let shared = Sound()
    var enabled = true { didSet { updateMusic() } }
    /// What should be playing; set every frame by the scene, acted on only when it changes.
    var mood: MusicMood = .afternoon { didSet { if mood != oldValue { updateMusic() } } }
    private let music: [MusicMood: AVAudioPlayer] = {
        var m: [MusicMood: AVAudioPlayer] = [:]
        for mood in MusicMood.allCases {
            guard let u = gameBundle.url(forResource: "music_\(mood.rawValue)", withExtension: "caf", subdirectory: "Resources"),
                  let p = try? AVAudioPlayer(contentsOf: u) else { continue }
            p.numberOfLoops = -1; p.volume = 0; p.prepareToPlay()
            m[mood] = p
        }
        return m
    }()
    private var urls: [SFX: URL] = [:]
    private var lastPlay: [SFX: TimeInterval] = [:]
    private var pool: [NSSound] = []

    private init() {
        for s in [SFX.dig, .brk, .place, .jump, .hurt, .pick, .craft, .swing, .bow, .hit, .die, .roar, .heal, .open] {
            if let u = gameBundle.url(forResource: s.rawValue, withExtension: "wav", subdirectory: "Resources") { urls[s] = u }
        }
        updateMusic()
    }
    /// Fades the chosen loop in from where it left off and the others out; a faded-out loop is paused so it costs nothing.
    private func updateMusic() {
        for (mood, p) in music {
            if enabled && mood == self.mood {
                if !p.isPlaying { p.volume = 0; p.play() }
                p.setVolume(mood.volume, fadeDuration: mood.fadeIn)
            } else if p.isPlaying {
                let fade: TimeInterval = enabled ? 2.5 : 0
                p.setVolume(0, fadeDuration: fade)
                DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { [weak self] in
                    guard let self = self, !(self.enabled && self.mood == mood) else { return }
                    p.pause()
                }
            }
        }
    }
    func play(_ s: SFX) {
        guard enabled, let u = urls[s] else { return }
        let now = Date().timeIntervalSince1970
        if let last = lastPlay[s], now - last < 0.05 { return }
        lastPlay[s] = now
        if let snd = NSSound(contentsOf: u, byReference: true) {
            snd.volume = 0.6
            pool.append(snd); if pool.count > 24 { pool.removeFirst() }
            snd.play()
        }
    }
}
