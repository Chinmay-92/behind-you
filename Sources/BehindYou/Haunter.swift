import AppKit

/// The rules: it never moves while you're watching. Every time you look away, it gets closer
/// and something real changes. On the last one, it waits for you to look back.
final class Haunter {
    enum Haunt: CaseIterable {
        case appear, whisper, wallpaper, cursor, heartbeat, darken
    }

    private let cfg: Config
    private let watcher: Watcher
    private let overlay: Overlay
    private let sound: Sound
    private var stage = 0
    private var token = 0
    private var looking = true
    private var armed = false
    private var over = false
    private var cursorUnlocked = false
    private var dimLevel: Float = 0
    private var bpm = 62.0
    private let work = DispatchQueue(label: "behindyou.photos", qos: .userInitiated)
    private var haunted: [Int: CGImage] = [:]
    private var lastPhotoStage = 0
    private let startedAt = Date()
    var onStage: ((Int, Int) -> Void)?
    var onFinished: (() -> Void)?

    init(cfg: Config, watcher: Watcher, overlay: Overlay, sound: Sound) {
        self.cfg = cfg
        self.watcher = watcher
        self.overlay = overlay
        self.sound = sound
        watcher.onChange = { [weak self] in self?.changed(looking: $0) }
        watcher.onStatus = { [weak self] s in
            guard let self else { return }
            overlay.status("\(s)   stage \(self.stage)/\(cfg.stages)")
        }
    }

    private func changed(looking now: Bool) {
        looking = now
        token += 1
        guard !over else { return }
        if now {
            if armed { finale() } else if stage > 0, Bool.random() || stage > cfg.stages / 2 { overlay.flicker() }
            return
        }
        guard !armed, Date().timeIntervalSince(startedAt) > cfg.grace else { return }
        let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + cfg.minAway) { [self] in
            guard t == token, !looking, !over else { return }
            advance()
        }
    }

    private func advance() {
        stage += 1
        onStage?(stage, cfg.stages)
        let p = Double(stage - 1) / Double(cfg.stages - 1)
        print("  \u{1B}[31m\(String(repeating: "▮", count: stage))\(String(repeating: "▯", count: cfg.stages - stage))\u{1B}[0m  you looked away.")

        if stage >= cfg.stages {
            armed = true
            overlay.placeGhost(progress: 1)
            sound.whisper("behind you", volume: 0.8)
            capture(progress: 1)
            return
        }
        overlay.placeGhost(progress: p)

        // Spread the haunts across however many stages there are.
        let all = Haunt.allCases, n = cfg.stages - 1
        for h in all[((stage - 1) * all.count / n)..<(stage * all.count / n)] { perform(h) }
        if cursorUnlocked { driftCursor() }
        if dimLevel > 0 { dimLevel = min(dimLevel + 0.06, 0.4); overlay.setDim(dimLevel) }
        if bpm > 62 { bpm += 14; sound.heartbeat(bpm: bpm) }
        capture(progress: p)
    }

    private func perform(_ h: Haunt) {
        switch h {
        case .appear:
            break
        case .whisper:
            sound.whisper("i see you")
        case .wallpaper:
            if cfg.wallpaper { WallpaperHaunt.haunt() }
        case .cursor:
            cursorUnlocked = cfg.cursor
            if cfg.notifications { notify("turn around.") }
        case .heartbeat:
            bpm = 70
            sound.heartbeat(bpm: bpm)
            sound.whisper("closer")
        case .darken:
            dimLevel = 0.16
            overlay.setDim(dimLevel)
            sound.whisper("don't look")
        }
    }

    /// Your cursor drifts to where its eyes are.
    private func driftCursor() {
        let target = overlay.ghostEyes
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func notify(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(text)\" with title \"someone\""]
        try? p.run()
    }

    /// Photographs you while you aren't looking, then puts it behind you.
    private func capture(progress p: Double) {
        let s = stage, t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            guard t == token, !looking, let photo = watcher.snapshot() else { return }
            work.async { [self] in
                guard let img = GhostArt.haunt(photo: photo, progress: p) else { return }
                DispatchQueue.main.async { [self] in
                    haunted[s] = img
                    lastPhotoStage = max(lastPhotoStage, s)
                }
            }
        }
    }

    private func finale() {
        over = true
        // Let the newest photo finish if it's still developing.
        work.async {
            DispatchQueue.main.async { [self] in
                sound.stopHeartbeat()
                sound.scream()
                let newest = haunted[lastPhotoStage]
                overlay.jumpscare(newest)
                print("  \u{1B}[31mit was behind you.\u{1B}[0m")
                let photos = haunted.keys.sorted().compactMap { haunted[$0] }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [self] in
                    overlay.gallery(photos, looks: stage) { [self] in
                        if cfg.keep { keep(photos) }
                        onFinished?()
                    }
                }
            }
        }
    }

    private func keep(_ photos: [CGImage]) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BehindYou/\(f.string(from: Date()))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, img) in photos.enumerated() {
            GhostArt.writePNG(img, to: dir.appendingPathComponent("look-away-\(i + 1).png"))
        }
        log("kept \(photos.count) photos in \(dir.path)")
    }
}
