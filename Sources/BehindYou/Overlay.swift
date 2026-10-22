import AVFoundation
import AppKit
import QuartzCore

/// A transparent, click-through layer over your real desktop. It's where the figure stands.
final class Overlay {
    let screen: NSScreen
    private let window: NSWindow
    private let root = CALayer()
    private let dim = CALayer()
    private let ghost = CALayer()
    private let stage = CALayer()
    private let hud = CATextLayer()
    private var ghostOpacity: Float = 0
    private var size: CGSize { screen.frame.size }

    init(screen: NSScreen, debug: Bool) {
        self.screen = screen
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = root
        root.frame = view.bounds
        window.contentView = view

        let scale = screen.backingScaleFactor
        for l in [dim, ghost, stage, hud] {
            l.contentsScale = scale
            root.addSublayer(l)
        }
        dim.frame = root.bounds
        dim.backgroundColor = .black
        dim.opacity = 0
        ghost.contents = GhostArt.figure
        ghost.contentsGravity = .resize
        ghost.opacity = 0
        stage.frame = root.bounds
        stage.backgroundColor = .black
        stage.contentsGravity = .resizeAspectFill
        stage.masksToBounds = true
        stage.opacity = 0

        hud.isHidden = !debug
        hud.frame = CGRect(x: 14, y: size.height - 64, width: 760, height: 22)
        hud.fontSize = 12
        hud.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        hud.foregroundColor = NSColor.systemGreen.cgColor
        hud.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor

        window.orderFrontRegardless()
    }

    private func still(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// Your own webcam in the corner — so a screen recording shows you looking away.
    func showCamera(_ session: AVCaptureSession) {
        let pip = AVCaptureVideoPreviewLayer(session: session)
        pip.videoGravity = .resizeAspectFill
        let w: CGFloat = 384, h: CGFloat = 216
        pip.frame = CGRect(x: size.width - w - 24, y: size.height - h - 52, width: w, height: h)
        pip.cornerRadius = 12
        pip.masksToBounds = true
        pip.borderWidth = 1
        pip.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        if let c = pip.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        root.addSublayer(pip)
    }

    func status(_ text: String) {
        still { hud.string = " " + text }
    }

    /// Teleports the figure. Only ever called while you're not looking.
    func placeGhost(progress p: Double) {
        let H = size.height * GhostArt.lerp(0.20, 1.25, pow(p, 1.25))
        let W = H * CGFloat(GhostArt.figure.width) / CGFloat(GhostArt.figure.height)
        let side: CGFloat = Bool.random() ? 1 : -1
        let cx = size.width * (0.5 + side * GhostArt.lerp(0.40, 0.04, p))
        let bottom = -size.height * GhostArt.lerp(0.0, 0.38, p)
        ghostOpacity = Float(GhostArt.lerp(0.38, 0.93, p))
        still {
            ghost.frame = CGRect(x: cx - W / 2, y: bottom, width: W, height: H)
            ghost.opacity = ghostOpacity
        }
    }

    /// Screen point (top-left origin, global) where the figure's eyes are.
    var ghostEyes: CGPoint {
        let f = ghost.frame
        let local = CGPoint(x: f.minX + f.width * GhostArt.headCenter.x, y: f.minY + f.height * GhostArt.headCenter.y)
        let primaryH = NSScreen.screens.first?.frame.height ?? size.height
        return CGPoint(x: screen.frame.minX + local.x, y: primaryH - (screen.frame.minY + local.y))
    }

    func setDim(_ a: Float) {
        still { dim.opacity = a }
    }

    /// It noticed you noticed.
    func flicker() {
        let o = ghostOpacity
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [o, 0, o, 0.1, o * 0.6, o]
        a.keyTimes = [0, 0.15, 0.3, 0.45, 0.7, 1]
        a.duration = 0.45
        ghost.add(a, forKey: "flicker")
    }

    // MARK: - Finale

    /// Full-screen jumpscare. With a photo: you, and what was behind you. Without: its face.
    func jumpscare(_ photo: CGImage?) {
        still {
            dim.opacity = 0
            ghost.removeAllAnimations()
            if let photo {
                stage.contents = photo
                stage.opacity = 1
                ghost.opacity = 0
            } else {
                // No photo: its head, right up against the glass, over your real desktop.
                let H = size.height * 0.8 / GhostArt.headHeight
                let W = H * CGFloat(GhostArt.figure.width) / CGFloat(GhostArt.figure.height)
                ghost.frame = CGRect(x: size.width / 2 - W / 2, y: size.height * 0.48 - H * GhostArt.headCenter.y,
                                     width: W, height: H)
                ghost.opacity = 1
                dim.opacity = 0.55
                stage.contents = nil
                stage.opacity = 0
            }
            root.insertSublayer(stage, below: ghost)
        }
        let shake = CAKeyframeAnimation(keyPath: "position")
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        shake.values = (0..<14).map { i in
            let m = CGFloat(14 - i) * 3.2
            return NSValue(point: CGPoint(x: c.x + .random(in: -m...m), y: c.y + .random(in: -m...m)))
        } + [NSValue(point: c)]
        shake.duration = 0.9
        let strobe = CAKeyframeAnimation(keyPath: "opacity")
        strobe.values = [1, 0.15, 1, 0.4, 1, 1]
        strobe.duration = 0.5
        for l in [stage, ghost] {
            l.add(shake, forKey: "shake")
            l.add(strobe, forKey: "strobe")
        }
    }

    /// "You looked away N times." Then every photo, with it closer each time.
    func gallery(_ photos: [CGImage], looks: Int, done: @escaping () -> Void) {
        let fade = { (l: CALayer, to: Float, dur: Double) in
            CATransaction.begin()
            CATransaction.setAnimationDuration(dur)
            l.opacity = to
            CATransaction.commit()
        }
        still {
            ghost.opacity = 0
            stage.contents = nil
            stage.backgroundColor = .black
            stage.opacity = 1
        }

        let title = text("you looked away \(looks) times.", size: 44, y: size.height * 0.84)
        root.addSublayer(title)
        fade(title, 1, 1.4)

        let cols = min(4, max(photos.count, 1))
        let rows = Int(ceil(Double(photos.count) / Double(cols)))
        let gap: CGFloat = 18
        let areaW = size.width * 0.82, areaH = size.height * 0.56
        let aspect: CGFloat = photos.first.map { CGFloat($0.width) / CGFloat($0.height) } ?? 16 / 9
        var cw = (areaW - gap * CGFloat(cols - 1)) / CGFloat(cols)
        var ch = cw / aspect
        if rows > 0, ch * CGFloat(rows) + gap * CGFloat(rows - 1) > areaH {
            ch = (areaH - gap * CGFloat(rows - 1)) / CGFloat(rows)
            cw = ch * aspect
        }
        let gridH = CGFloat(rows) * ch + CGFloat(max(rows - 1, 0)) * gap
        let top = size.height * 0.47 + gridH / 2
        for (i, img) in photos.enumerated() {
            let r = i / cols, c = i % cols
            let inRow = min(cols, photos.count - r * cols)
            let rowW = CGFloat(inRow) * cw + CGFloat(inRow - 1) * gap
            let cell = CALayer()
            cell.contentsScale = screen.backingScaleFactor
            cell.contents = img
            cell.contentsGravity = .resizeAspectFill
            cell.masksToBounds = true
            cell.frame = CGRect(x: (size.width - rowW) / 2 + CGFloat(c) * (cw + gap),
                                y: top - CGFloat(r + 1) * ch - CGFloat(r) * gap, width: cw, height: ch)
            cell.opacity = 0
            root.addSublayer(cell)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6 + Double(i) * 0.45) { fade(cell, 1, 0.6) }
        }

        let t1 = 1.6 + Double(photos.count) * 0.45 + 0.8
        let line = text("I was there every time.", size: 30, y: size.height * (photos.isEmpty ? 0.5 : 0.10))
        root.addSublayer(line)
        DispatchQueue.main.asyncAfter(deadline: .now() + t1) { fade(line, 1, 1.5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + t1 + 5) { fade(self.root, 0, 2.5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + t1 + 7.8) { done() }
    }

    private func text(_ s: String, size pt: CGFloat, y: CGFloat) -> CATextLayer {
        let t = CATextLayer()
        t.contentsScale = screen.backingScaleFactor
        let font = NSFont(name: "Baskerville-Italic", size: pt) ?? NSFont.systemFont(ofSize: pt)
        t.string = NSAttributedString(string: s, attributes: [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.86, green: 0.83, blue: 0.79, alpha: 1),
        ])
        t.alignmentMode = .center
        t.frame = CGRect(x: 0, y: y - pt * 0.6, width: size.width, height: pt * 1.5)
        t.opacity = 0
        return t
    }

    func close() {
        window.orderOut(nil)
    }
}
