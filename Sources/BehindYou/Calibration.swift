import AppKit

/// A guided 35 seconds: look, turn away, look down, close your eyes. Prints what the watcher saw
/// in each phase so the thresholds can be set from a real face instead of guesses.
final class Calibration {
    struct Phase {
        var say: String
        var seconds: Double
        /// What the right answer is for this phase.
        var shouldLook: Bool
    }

    private let phases = [
        Phase(say: "Look at the screen normally. Read something.", seconds: 7, shouldLook: true),
        Phase(say: "Turn your head to the left, away from the screen.", seconds: 6, shouldLook: false),
        Phase(say: "Now turn to the right.", seconds: 6, shouldLook: false),
        Phase(say: "Look down at your phone, or your lap.", seconds: 6, shouldLook: false),
        Phase(say: "Close your eyes.", seconds: 5, shouldLook: false),
        Phase(say: "Look back at the screen.", seconds: 5, shouldLook: true),
    ]
    private let watcher: GazeWatcher
    private var current = -1
    private var phaseStart = Date()
    private var readings: [[GazeWatcher.Reading]]

    init(_ cfg: Config) {
        watcher = GazeWatcher(cfg)
        readings = Array(repeating: [], count: phases.count)
    }

    func run() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        watcher.onReading = { [unowned self] r in
            // Skip the first second of each phase while you move.
            guard current >= 0, Date().timeIntervalSince(phaseStart) > 1.2 else { return }
            readings[current].append(r)
        }
        watcher.start { [unowned self] error in
            if let error {
                print("  \(error)")
                exit(1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.next() }
        }
        NSApplication.shared.run()
        exit(0)
    }

    private func next() {
        current += 1
        guard current < phases.count else { return report() }
        let p = phases[current]
        print("  \u{1B}[1m\(current + 1). \(p.say)\u{1B}[0m")
        speak(p.say)
        phaseStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + p.seconds) { self.next() }
    }

    private func speak(_ s: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = [s]
        try? p.run()
    }

    private func report() {
        speak("Done.")
        watcher.stop()
        func med(_ xs: [Double]) -> Double { xs.isEmpty ? .nan : xs.sorted()[xs.count / 2] }
        func pct(_ xs: [Double], _ q: Double) -> Double { xs.isEmpty ? .nan : xs.sorted()[min(xs.count - 1, Int(Double(xs.count) * q))] }
        func q(_ xs: [Double]) -> String {
            xs.isEmpty ? "      —        " : String(format: "%+.2f (%+.2f..%+.2f)", pct(xs, 0.5), pct(xs, 0.1), pct(xs, 0.9))
        }
        print("\n  phase           n  face%   yaw (p10..p90)        pitch (p10..p90)      turn (p10..p90)       eyes (p10..p90)       correct%")
        let names = ["screen", "left", "right", "down", "eyes shut", "screen again"]
        for (i, (p, rs)) in zip(phases, readings).enumerated() {
            let f = rs.filter(\.face)
            let correct = rs.filter { $0.looking == p.shouldLook }.count
            print("  " + names[i].padding(toLength: 14, withPad: " ", startingAt: 0)
                  + String(format: "%3d  %4.0f   ", rs.count, 100 * Double(f.count) / Double(max(rs.count, 1)))
                  + [q(f.map(\.yaw)), q(f.map(\.pitch)), q(f.map(\.turn)), q(f.map(\.eyes))].joined(separator: "   ")
                  + String(format: "   %4.0f", 100 * Double(correct) / Double(max(rs.count, 1))))
        }
        print("")
        exit(0)
    }
}
