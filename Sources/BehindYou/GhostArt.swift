import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Procedural art: the figure itself, and putting it behind you in a photo.
enum GhostArt {
    static let ci = CIContext(options: [.cacheIntermediates: false])
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Where the head sits inside the figure image, as a fraction of its size.
    static let headCenter = CGPoint(x: 0.5, y: 0.83)
    static let headHeight: CGFloat = 0.125

    static let figure: CGImage = makeFigure(width: 700, height: 1400)

    static func bitmap(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// A tall shadow figure with long arms, a tilted head and two pinpoint eyes.
    static func makeFigure(width: Int, height: Int) -> CGImage {
        let w = CGFloat(width), h = CGFloat(height)
        let ctx = bitmap(width, height)

        let P = { (x: CGFloat, y: CGFloat) in CGPoint(x: w * x, y: h * y) }
        let path = CGMutablePath()
        // Head: too long, tilted a little too far.
        let hc = P(headCenter.x, headCenter.y)
        let tilt = CGAffineTransform(translationX: hc.x, y: hc.y).rotated(by: 0.17)
        path.addEllipse(in: CGRect(x: -w * 0.085, y: -h * headHeight / 2, width: w * 0.17, height: h * headHeight),
                        transform: tilt)

        // One side of the body, from the neck down to the waist. `s` mirrors it; `long` stretches the arm.
        func half(_ s: CGFloat, long: CGFloat) -> [CGPoint] {
            let x = { (v: CGFloat) in 0.5 + s * (v - 0.5) }
            var pts = [P(x(0.465), 0.755), P(x(0.40), 0.715), P(x(0.29), 0.685), P(x(0.25), 0.62),
                       P(x(0.21), 0.40), P(x(0.185), 0.16 - long)]
            // Fingers: four of them, too long.
            let tips: [(CGFloat, CGFloat)] = [(0.168, 0.06), (0.192, 0.04), (0.222, 0.05), (0.250, 0.085)]
            for (i, t) in tips.enumerated() {
                pts.append(P(x(t.0), t.1 - long))
                pts.append(P(x(0.195 + CGFloat(i) * 0.022), 0.15 - long))
            }
            pts += [P(x(0.265), 0.17 - long), P(x(0.29), 0.40), P(x(0.33), 0.55), P(x(0.36), 0.30), P(x(0.37), 0.0)]
            return pts
        }
        let left = half(1, long: 0), right = half(-1, long: 0.025)
        path.addLines(between: left + right.reversed())
        path.closeSubpath()

        ctx.addPath(path)
        ctx.clip()
        let ink = { (a: CGFloat) in CGColor(srgbRed: 0.015, green: 0.015, blue: 0.025, alpha: a) }
        let fade = CGGradient(colorsSpace: space, colors: [ink(0), ink(0.85), ink(1)] as CFArray,
                              locations: [0, 0.22, 1])!
        ctx.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let body = ctx.makeImage()!

        // Wisp the edges with noise so it never looks drawn.
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let noise = CIFilter.randomGenerator().outputImage!.applyingGaussianBlur(sigma: 5).cropped(to: rect)
        let wisp = CIFilter.displacementDistortion()
        wisp.inputImage = CIImage(cgImage: body).clampedToExtent()
        wisp.displacementImage = noise
        wisp.scale = Float(w) * 0.09
        let soft = wisp.outputImage!.applyingGaussianBlur(sigma: Double(w) * 0.005).cropped(to: rect)
        let out = bitmap(width, height)
        let shape = ci.createCGImage(soft, from: rect)!
        // A faint pale edge, so it still reads against dark windows.
        out.saveGState()
        out.setShadow(offset: .zero, blur: w * 0.03, color: CGColor(srgbRed: 0.78, green: 0.8, blue: 0.86, alpha: 0.55))
        out.draw(shape, in: rect)
        out.restoreGState()
        out.draw(shape, in: rect)

        // Eyes: pinpoints with a glow, slightly mismatched.
        let eyes = [CGPoint(x: -w * 0.034, y: h * 0.006), CGPoint(x: w * 0.036, y: h * 0.003)]
        for (i, e) in eyes.enumerated() {
            let p = e.applying(tilt)
            let r = w * (i == 0 ? 0.0095 : 0.0082)
            for (blur, a) in [(w * 0.05, 0.55), (w * 0.018, 0.95)] as [(CGFloat, CGFloat)] {
                out.setShadow(offset: .zero, blur: blur, color: CGColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: a))
                out.setFillColor(CGColor(srgbRed: 1, green: 0.97, blue: 0.93, alpha: 1))
                out.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.8, width: r * 2, height: r * 1.6))
            }
        }
        return out.makeImage()!
    }

    // MARK: - Photo haunting

    /// Puts the figure *behind* the person in `photo`. progress 0 = far away, 1 = at your shoulder.
    static func haunt(photo: CGImage, progress p: Double) -> CGImage? {
        let base = CIImage(cgImage: photo)
        let W = base.extent.width, H = base.extent.height
        let person = findPerson(photo)

        let ghostH = H * lerp(0.62, 1.45, p)
        let s = ghostH / CGFloat(figure.height)
        let ghostW = CGFloat(figure.width) * s
        let headW = ghostW * 0.17
        var cx: CGFloat, headY: CGFloat
        if let person {
            // Beside your head, on whichever side has more room — closer every time.
            let roomLeft = person.headLeft, roomRight = 1 - person.headRight
            let side: CGFloat = roomRight >= roomLeft ? 1 : -1
            let edge = (side > 0 ? person.headRight : person.headLeft) * W
            cx = edge + side * headW * lerp(2.6, 0.35, p)
            headY = min(max(person.top * H - H * lerp(0.04, 0.09, p), H * 0.42), H * 0.80)
        } else {
            cx = W * lerp(0.82, 0.62, p)
            headY = H * lerp(0.6, 0.68, p)
        }
        let x = cx - ghostW / 2
        let y = headY - headCenter.y * ghostH

        var ghost = CIImage(cgImage: figure)
            .transformed(by: CGAffineTransform(scaleX: s, y: s).concatenating(.init(translationX: x, y: y)))
        // Far away = more out of focus, fainter.
        ghost = ghost.applyingGaussianBlur(sigma: Double(W / 1000) * lerp(5, 1.5, p)).cropped(to: base.extent)
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = ghost
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: lerp(0.62, 0.95, p))
        let room = alpha.outputImage!.composited(over: base)

        var result = room
        if let mask = person?.mask {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = base
            blend.backgroundImage = room
            blend.maskImage = mask
            result = blend.outputImage!
        }
        return ci.createCGImage(grade(result, extent: base.extent), from: base.extent)
    }

    struct Person {
        var mask: CIImage
        /// All 0...1, bottom-left origin like Core Image.
        var top: CGFloat
        var headLeft: CGFloat
        var headRight: CGFloat
    }

    /// Segments the person in the photo and finds where their head is.
    static func findPerson(_ photo: CGImage) -> Person? {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .accurate
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? VNImageRequestHandler(cgImage: photo, options: [:]).perform([req])
        guard let buf = req.results?.first?.pixelBuffer else { return nil }
        let mw = CVPixelBufferGetWidth(buf), mh = CVPixelBufferGetHeight(buf)

        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(buf)
        let px = raw.assumingMemoryBound(to: UInt8.self)
        let on = { (x: Int, y: Int) in px[y * row + x] > 128 }

        // Rows run top-down in the buffer.
        guard let topRow = (0..<mh).first(where: { y in stride(from: 0, to: mw, by: 2).contains { on($0, y) } })
        else { return nil }
        var left = mw, right = 0
        for y in topRow..<min(mh, topRow + mh / 4) {
            for x in 0..<mw where on(x, y) {
                left = min(left, x)
                right = max(right, x)
            }
        }
        guard right > left else { return nil }

        let mask = CIImage(cvPixelBuffer: buf).transformed(by: CGAffineTransform(
            scaleX: CGFloat(photo.width) / CGFloat(mw), y: CGFloat(photo.height) / CGFloat(mh)))
        return Person(mask: mask, top: 1 - CGFloat(topRow) / CGFloat(mh),
                      headLeft: CGFloat(left) / CGFloat(mw), headRight: CGFloat(right) / CGFloat(mw))
    }

    /// Cold, drained, grainy — like footage you weren't meant to see.
    static func grade(_ img: CIImage, extent: CGRect) -> CIImage {
        let cc = CIFilter.colorControls()
        cc.inputImage = img
        cc.saturation = 0.22
        cc.brightness = -0.07
        cc.contrast = 1.18
        let tint = CIFilter.colorMatrix()
        tint.inputImage = cc.outputImage
        tint.rVector = CIVector(x: 0.92, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.98, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 1.06, w: 0)
        let vig = CIFilter.vignetteEffect()
        vig.inputImage = tint.outputImage
        vig.center = CGPoint(x: extent.midX, y: extent.midY)
        vig.radius = Float(min(extent.width, extent.height) * 0.7)
        vig.intensity = 0.9
        vig.falloff = 0.55
        let grain = CIFilter.colorMatrix()
        grain.inputImage = CIFilter.randomGenerator().outputImage!.cropped(to: extent)
        grain.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grain.gVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grain.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grain.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.07)
        return grain.outputImage!.composited(over: vig.outputImage!).cropped(to: extent)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(min(max(t, 0), 1))
    }

    static func writePNG(_ img: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
