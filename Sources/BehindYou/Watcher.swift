import AVFoundation
import AppKit
import CoreImage
import Vision

/// Something that knows whether you're looking at the screen.
protocol Watcher: AnyObject {
    var onChange: ((Bool) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start(_ done: @escaping (String?) -> Void)
    func stop()
    /// A mirrored frame from right now, if there is a camera.
    func snapshot() -> CGImage?
}

// MARK: - Webcam + Vision

final class GazeWatcher: NSObject, Watcher, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Reading {
        var face = false
        var yaw = 0.0, pitch = 0.0, turn = 0.0, eyes = 0.0
        var closed = false
        /// Undebounced verdict for this frame.
        var looking = false
    }

    var onChange: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReading: ((Reading) -> Void)?

    let session = AVCaptureSession()
    private let cfg: Config
    private let queue = DispatchQueue(label: "behindyou.gaze")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var lastRun: CFTimeInterval = 0
    private var looking = true
    private var pendingSince: CFTimeInterval?
    private var openness: [Double] = []
    /// Your resting pose in front of the screen. Webcams sit off to the side, so "looking at the
    /// screen" is rarely yaw 0 — everything is measured from here.
    private var baseline: (yaw: Double, pitch: Double, turn: Double)?
    private var learning: [(Double, Double, Double)] = []

    init(_ cfg: Config) { self.cfg = cfg }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    func start(_ done: @escaping (String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            done(configure())
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { done(ok ? self.configure() : "camera access denied") }
            }
        default:
            done("camera access denied — allow it in System Settings › Privacy & Security › Camera")
        }
    }

    private func configure() -> String? {
        let all = Self.cameras()
        let device: AVCaptureDevice?
        if let name = cfg.cameraName {
            device = all.first { $0.localizedName.localizedCaseInsensitiveContains(name) }
        } else {
            // Prefer the camera on the desk over a phone.
            device = all.first { $0.deviceType != .continuityCamera } ?? all.first
        }
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            return "no camera found (try --list-cameras)"
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return "can't use \(device.localizedName)" }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(out) else { return "can't read frames from \(device.localizedName)" }
        session.addOutput(out)
        session.commitConfiguration()
        queue.async { self.session.startRunning() }
        log("watching through: \(device.localizedName)")
        return nil
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    func snapshot() -> CGImage? {
        lock.lock()
        let pb = latest
        lock.unlock()
        guard let pb else { return nil }
        let img = CIImage(cvPixelBuffer: pb).oriented(.upMirrored)
        return GhostArt.ci.createCGImage(img, from: img.extent)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        lock.lock()
        latest = pb
        lock.unlock()

        let now = CACurrentMediaTime()
        guard now - lastRun > 0.07 else { return }
        lastRun = now
        let r = read(pb)
        debounce(r.looking, now: now)

        let line = (looking ? "● WATCHING  " : "○ AWAY  ") + (r.face ? String(
            format: "yaw %+.2f  pitch %+.2f  turn %+.2f  eyes %.2f%@",
            r.yaw, r.pitch, r.turn, r.eyes, r.closed ? " CLOSED" : "") : "no face")
        DispatchQueue.main.async {
            self.onStatus?(line)
            self.onReading?(r)
        }
    }

    private func read(_ pb: CVPixelBuffer) -> Reading {
        // Revision 3 gives continuous yaw/pitch; the landmarks request alone only gives 45° steps.
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up)
        let rects = VNDetectFaceRectanglesRequest()
        rects.revision = VNDetectFaceRectanglesRequestRevision3
        try? handler.perform([rects])
        guard let box = (rects.results ?? [])
            .filter({ $0.boundingBox.width > 0.07 })
            .max(by: { $0.boundingBox.width < $1.boundingBox.width })
        else { return Reading() }
        let req = VNDetectFaceLandmarksRequest()
        req.revision = VNDetectFaceLandmarksRequestRevision3
        req.inputFaceObservations = [box]
        try? handler.perform([req])
        let face = req.results?.first ?? box

        var r = Reading(face: true)
        r.yaw = box.yaw?.doubleValue ?? 0
        r.pitch = box.pitch?.doubleValue ?? 0
        if let lm = face.landmarks, let l = lm.leftEye, let rt = lm.rightEye, let nose = lm.nose {
            let le = center(l.normalizedPoints), re = center(rt.normalizedPoints), n = center(nose.normalizedPoints)
            let span = max(abs(re.x - le.x), 0.01)
            r.turn = Double((n.x - (le.x + re.x) / 2) / span)
            r.eyes = (aspect(l.normalizedPoints) + aspect(rt.normalizedPoints)) / 2
            openness.append(r.eyes)
            if openness.count > 150 { openness.removeFirst() }
            if cfg.blink, openness.count > 20 {
                let sorted = openness.sorted()
                r.closed = r.eyes < sorted[Int(Double(sorted.count) * 0.85)] * cfg.eyesClosed
            }
        }
        guard let b = baseline else {
            // The first couple of seconds: you just launched it, so you're looking at the screen.
            learning.append((r.yaw, r.pitch, r.turn))
            if learning.count >= 30 {
                func med(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
                baseline = (med(learning.map(\.0)), med(learning.map(\.1)), med(learning.map(\.2)))
                log(String(format: "learned your resting pose: yaw %+.2f  pitch %+.2f  turn %+.2f",
                           baseline!.yaw, baseline!.pitch, baseline!.turn))
            }
            r.looking = !r.closed
            return r
        }
        r.looking = abs(r.yaw - b.yaw) < cfg.maxYaw && abs(r.pitch - b.pitch) < cfg.maxPitch
            && abs(r.turn - b.turn) < cfg.maxTurn && !r.closed
        if r.looking {
            // Drift slowly with your posture.
            let k = 0.01
            baseline = (b.yaw + (r.yaw - b.yaw) * k, b.pitch + (r.pitch - b.pitch) * k, b.turn + (r.turn - b.turn) * k)
        }
        return r
    }

    /// A blink or a twitch shouldn't count.
    private func debounce(_ raw: Bool, now: CFTimeInterval) {
        guard raw != looking else {
            pendingSince = nil
            return
        }
        if pendingSince == nil { pendingSince = now }
        if now - pendingSince! >= (raw ? 0.15 : 0.35) {
            looking = raw
            pendingSince = nil
            DispatchQueue.main.async { self.onChange?(raw) }
        }
    }

    private func center(_ pts: [CGPoint]) -> CGPoint {
        let s = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: s.x / CGFloat(max(pts.count, 1)), y: s.y / CGFloat(max(pts.count, 1)))
    }

    private func aspect(_ pts: [CGPoint]) -> Double {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0)
        return w > 0 ? Double(((ys.max() ?? 0) - (ys.min() ?? 0)) / w) : 0
    }
}

// MARK: - Autopilot: looks away every few seconds (for testing without a person)

final class AutopilotWatcher: Watcher {
    var onChange: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    private var timer: Timer?
    private var looking = true
    private let photo: CGImage?

    init(photo path: String?) {
        photo = path.flatMap { CGImageSourceCreateWithURL(URL(fileURLWithPath: $0) as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    func start(_ done: @escaping (String?) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            looking.toggle()
            onChange?(looking)
            onStatus?(looking ? "● WATCHING (autopilot)" : "○ AWAY (autopilot)")
        }
        log("autopilot: looking away every 3s")
        done(nil)
    }

    func stop() { timer?.invalidate() }
    func snapshot() -> CGImage? { photo }
}
