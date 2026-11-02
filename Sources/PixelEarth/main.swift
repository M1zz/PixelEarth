import AppKit
import SpriteKit

/// Minimal AppKit bootstrap: one window hosting an SKView. No storyboard, no dependencies.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var skView: SKView!
    var scene: GameScene!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(1440, screen.width - 80), h = min(860, screen.height - 80)
        let rect = NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Pixel Earth"
        window.minSize = NSSize(width: 900, height: 560)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        skView = SKView(frame: NSRect(origin: .zero, size: rect.size))
        skView.autoresizingMask = [.width, .height]
        skView.preferredFramesPerSecond = 60
        skView.ignoresSiblingOrder = false   // the HUD stacks by insertion order
        skView.showsFPS = false
        window.contentView = skView

        scene = GameScene(size: rect.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        // Set the Dock icon from the bundle directly, so a stale Launch Services record from an older build cannot hide it.
        if let icon = NSImage(named: "AppIcon") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) {
            NSApp.applicationIconImage = icon
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Pixel Earth 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Pixel Earth 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "보기")
        viewMenu.addItem(withTitle: "전체 화면", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = viewMenu
        NSApp.mainMenu = main
    }

    func windowWillClose(_ notification: Notification) { scene?.save(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { scene?.save() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
