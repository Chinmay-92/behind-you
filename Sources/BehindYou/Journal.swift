import AppKit

func log(_ s: String) {
    print("  \u{1B}[2m\(s)\u{1B}[0m")
}

/// Everything it touches is written down *before* it's touched, so it can always be put back —
/// even after a crash (`behindyou --exorcise`).
struct Journal: Codable {
    struct Wallpaper: Codable {
        var screen: UInt32
        var url: String
        var scaling: Int?
        var clipping: Bool?
        var fill: [CGFloat]?
    }

    var wallpapers: [Wallpaper] = []

    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BehindYou", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let file = dir.appendingPathComponent("journal.json")
    /// Haunted wallpapers and photos live here and are deleted on exorcism.
    static let scratch = dir.appendingPathComponent("run", isDirectory: true)

    static func load() -> Journal? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Journal.self, from: data)
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }

    /// Puts everything back the way it was.
    static func exorcise(quiet: Bool = false) {
        if let j = load() {
            for w in j.wallpapers {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == w.screen }) else { continue }
                var opts: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
                if let s = w.scaling { opts[.imageScaling] = NSNumber(value: s) }
                if let c = w.clipping { opts[.allowClipping] = NSNumber(value: c) }
                if let f = w.fill, f.count == 4 {
                    opts[.fillColor] = NSColor(srgbRed: f[0], green: f[1], blue: f[2], alpha: f[3])
                }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: w.url), for: screen, options: opts)
                    if !quiet { log("wallpaper restored: \(w.url)") }
                } catch {
                    log("could not restore wallpaper \(w.url): \(error.localizedDescription)")
                }
            }
            try? FileManager.default.removeItem(at: file)
        }
        try? FileManager.default.removeItem(at: scratch)
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// MARK: - Your actual wallpaper

enum WallpaperHaunt {
    private static let queue = DispatchQueue(label: "behindyou.wallpaper", qos: .userInitiated)

    /// Darkens your real wallpaper and puts something in it, far away. Journals the original first.
    static func haunt() {
        var journal = Journal.load() ?? Journal()
        try? FileManager.default.createDirectory(at: Journal.scratch, withIntermediateDirectories: true)
        for screen in NSScreen.screens {
            guard let original = NSWorkspace.shared.desktopImageURL(for: screen) else {
                log("no wallpaper URL for \(screen.localizedName)")
                continue
            }
            let id = screen.displayID
            if !journal.wallpapers.contains(where: { $0.screen == id }) {
                let opts = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                journal.wallpapers.append(.init(
                    screen: id, url: original.path,
                    scaling: (opts[.imageScaling] as? NSNumber)?.intValue,
                    clipping: (opts[.allowClipping] as? NSNumber)?.boolValue,
                    fill: (opts[.fillColor] as? NSColor)?.usingColorSpace(.sRGB).map {
                        [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent]
                    }))
                journal.save()
            }
            let size = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                              height: screen.frame.height * screen.backingScaleFactor)
            // Rendering a 5K wallpaper takes a moment; don't freeze the overlay while it does.
            queue.async {
                guard let img = render(original: original, size: size) else { return }
                let url = Journal.scratch.appendingPathComponent("wallpaper-\(id)-\(UUID().uuidString.prefix(6)).png")
                GhostArt.writePNG(img, to: url)
                DispatchQueue.main.async {
                    do {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                            .allowClipping: NSNumber(value: true),
                        ])
                    } catch {
                        log("could not change wallpaper on \(screen.localizedName): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    static func render(original: URL, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        let ctx = GhostArt.bitmap(w, h)
        let full = CGRect(origin: .zero, size: size)

        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        if let src = CGImageSourceCreateWithURL(original as CFURL, nil),
           let img = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb as CFDictionary) {
            // Aspect-fill, drained of colour.
            let s = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
            let dw = CGFloat(img.width) * s, dh = CGFloat(img.height) * s
            let drained = GhostArt.grade(CIImage(cgImage: img), extent: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            if let g = GhostArt.ci.createCGImage(drained, from: drained.extent) {
                ctx.draw(g, in: CGRect(x: (size.width - dw) / 2, y: (size.height - dh) / 2, width: dw, height: dh))
            }
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.42))
            ctx.fill(full)
        } else {
            ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
            ctx.fill(full)
        }

        // Something standing in your wallpaper. Small. Far away. Facing you.
        let gh = size.height * 0.34
        let gw = gh * CGFloat(GhostArt.figure.width) / CGFloat(GhostArt.figure.height)
        ctx.setAlpha(0.85)
        ctx.draw(GhostArt.figure, in: CGRect(x: size.width * 0.71, y: size.height * 0.06, width: gw, height: gh))
        return ctx.makeImage()
    }
}
