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
    var onChange: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?

    private let cfg: Config
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "behindyou.gaze")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var lastRun: CFTimeInterval = 0
    private var looking = true
    private var pendingSince: CFTimeInterval?
    private var openness: [Double] = []

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
            done("camera access denied — allow it in System Settings › Privacy & Security › Camera, or use --no-camera")
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
            return "no camera found (try --list-cameras or --no-camera)"
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
        evaluate(pb, now: now)
    }

    private func evaluate(_ pb: CVPixelBuffer, now: CFTimeInterval) {
        let req = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([req])
        let face = (req.results ?? [])
            .filter { $0.boundingBox.width > 0.07 }
            .max { $0.boundingBox.width < $1.boundingBox.width }

        var raw = false
        var status = "no face"
        if let face {
            let yaw = face.yaw?.doubleValue ?? 0
            let pitch = face.pitch?.doubleValue ?? 0
            var turn = 0.0, open = 1.0, closed = false
            if let lm = face.landmarks, let l = lm.leftEye, let r = lm.rightEye, let nose = lm.nose {
                let le = center(l.normalizedPoints), re = center(r.normalizedPoints), n = center(nose.normalizedPoints)
                let span = max(abs(re.x - le.x), 0.01)
                turn = Double((n.x - (le.x + re.x) / 2) / span)
                open = (aspect(l.normalizedPoints) + aspect(r.normalizedPoints)) / 2
                openness.append(open)
                if openness.count > 150 { openness.removeFirst() }
                if cfg.blink, openness.count > 20 {
                    let sorted = openness.sorted()
                    let baseline = sorted[Int(Double(sorted.count) * 0.85)]
                    closed = open < baseline * 0.55
                }
            }
            let facing = abs(yaw) < 0.5 && abs(pitch) < 0.6 && abs(turn) < 0.42
            raw = facing && !closed
            status = String(format: "yaw %+.2f  pitch %+.2f  turn %+.2f  eyes %.2f%@",
                            yaw, pitch, turn, open, closed ? " CLOSED" : "")
        }

        // Debounce: a blink or a twitch shouldn't count.
        if raw != looking {
            if pendingSince == nil { pendingSince = now }
            if now - pendingSince! >= (raw ? 0.15 : 0.35) {
                looking = raw
                pendingSince = nil
                let v = raw
                DispatchQueue.main.async { self.onChange?(v) }
            }
        } else {
            pendingSince = nil
        }
        let line = (looking ? "● WATCHING  " : "○ AWAY  ") + status
        DispatchQueue.main.async { self.onStatus?(line) }
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

// MARK: - No camera: you "look away" when you stop touching the machine

final class IdleWatcher: Watcher {
    var onChange: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    private let threshold: TimeInterval
    private var timer: Timer?
    private var looking = true

    init(threshold: TimeInterval) { self.threshold = threshold }

    func start(_ done: @escaping (String?) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        log("no camera: it moves when you stop touching your computer for \(Int(threshold))s")
        done(nil)
    }

    private func tick() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let now = idle < threshold
        if now != looking {
            looking = now
            onChange?(now)
        }
        onStatus?(String(format: "%@  idle %.1fs", looking ? "● WATCHING" : "○ AWAY", idle))
    }

    func stop() { timer?.invalidate() }
    func snapshot() -> CGImage? { nil }
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
