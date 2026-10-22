import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let (cfg, command) = Config.parse(Array(CommandLine.arguments.dropFirst()))

switch command {
case .help:
    print(Config.usage)
    exit(0)
case .exorcise:
    Journal.exorcise()
    print("  exorcised. everything is back where it was.")
    exit(0)
case .listCameras:
    for d in GazeWatcher.cameras() { print("  \(d.localizedName)") }
    exit(0)
case let .preview(photo):
    let out = URL(fileURLWithPath: "preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    GhostArt.writePNG(GhostArt.figure, to: out.appendingPathComponent("figure.png"))
    if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
       let wall = WallpaperHaunt.render(original: url, size: CGSize(width: 1920, height: 1200)) {
        GhostArt.writePNG(wall, to: out.appendingPathComponent("wallpaper.png"))
    }
    if let photo, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: photo) as CFURL, nil),
       let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        for p in [0.0, 0.5, 1.0] {
            if let h = GhostArt.haunt(photo: img, progress: p) {
                GhostArt.writePNG(h, to: out.appendingPathComponent("haunted-\(Int(p * 100)).png"))
            }
        }
    }
    print("  wrote \(out.path)")
    exit(0)
case .haunt:
    break
}

// A previous run that crashed gets cleaned up before anything else.
if Journal.load() != nil {
    log("found a previous haunting that never ended — exorcising it first.")
    Journal.exorcise()
}

print("""

  \u{1B}[1mB E H I N D   Y O U\u{1B}[0m

  It only moves when you aren't looking.

  While this runs, every time you look away it will get closer, and it may:
    · stand on your screen          · darken your real wallpaper
    · move your cursor              · whisper, send you a notification
    · photograph you (kept in memory only, never uploaded)

  Everything is put back when it ends, when you press Ctrl-C, or via the 🕯 menu.
  Keep working. Don't look away.

""")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else {
    print("no screen")
    exit(1)
}
let overlay = Overlay(screen: screen, debug: cfg.debug)
let sound = Sound(enabled: cfg.sound)
let watcher: Watcher
if cfg.autopilot {
    watcher = AutopilotWatcher(photo: cfg.autopilotPhoto)
} else if cfg.useCamera {
    watcher = GazeWatcher(cfg)
} else {
    watcher = IdleWatcher(threshold: cfg.idleThreshold)
}
let haunter = Haunter(cfg: cfg, watcher: watcher, overlay: overlay, sound: sound)

func end(_ message: String) -> Never {
    watcher.stop()
    sound.stop()
    overlay.close()
    Journal.exorcise(quiet: true)
    print("\n  \(message)\n")
    exit(0)
}

// Menu-bar candle: always one click from making it stop.
final class Candle: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let progress = NSMenuItem(title: "it hasn't moved yet", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        item.button?.title = "🕯"
        let menu = NSMenu()
        menu.addItem(progress)
        menu.addItem(.separator())
        let ex = NSMenuItem(title: "Exorcise (restore everything & quit)", action: #selector(exorcise), keyEquivalent: "q")
        ex.target = self
        menu.addItem(ex)
        item.menu = menu
    }

    @objc func exorcise() { end("exorcised. everything is back where it was.") }
}
let candle = Candle()

haunter.onStage = { s, n in candle.progress.title = "it has moved \(s) of \(n) times" }
haunter.onFinished = { end("it's gone. for now. your wallpaper is back.") }

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { end("exorcised. everything is back where it was.") }
    src.resume()
    signalSources.append(src)
}

watcher.start { error in
    if let error {
        print("  \(error)")
        end("nothing happened.")
    }
}

app.run()
