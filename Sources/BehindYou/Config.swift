import Foundation

enum Command {
    case haunt
    case lightsOn
    case calibrate
    case preview(photo: String?)
    case listCameras
    case help
}

struct Config {
    /// Number of look-aways before the finale.
    var stages = 7
    var cameraName: String?
    var autopilot = false
    var autopilotPhoto: String?
    var debug = false
    var pip = false
    var record: String?
    var keep = false
    var wallpaper = true
    var lightsOut = true
    var sound = true
    var blink = true
    /// How long you must be looking away before it moves.
    var minAway: TimeInterval = 0.5
    /// Calm period after launch before anything can happen.
    var grace: TimeInterval = 4

    // Gaze thresholds: how far from your resting pose counts as looking away (tune with --calibrate).
    var maxYaw = 0.45
    var maxPitch = 0.4
    var maxTurn = 0.3
    /// Eyes count as closed below this fraction of your own open-eye baseline.
    var eyesClosed = 0.55

    static func parse(_ args: [String]) -> (Config, Command) {
        var c = Config()
        var cmd = Command.haunt
        var i = 0
        func next() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        func hasValue() -> Bool { i + 1 < args.count && !args[i + 1].hasPrefix("--") }
        while i < args.count {
            switch args[i] {
            case "--lights-on": cmd = .lightsOn
            case "--calibrate": cmd = .calibrate
            case "--preview": cmd = .preview(photo: hasValue() ? next() : nil)
            case "--list-cameras": cmd = .listCameras
            case "-h", "--help": cmd = .help
            case "--stages": c.stages = max(2, Int(next() ?? "") ?? c.stages)
            case "--fast":
                c.stages = 5
                c.minAway = 0.35
                c.grace = 2
            case "--camera": c.cameraName = next()
            case "--autopilot":
                c.autopilot = true
                if hasValue() { c.autopilotPhoto = next() }
            case "--debug": c.debug = true
            case "--pip": c.pip = true
            case "--record": c.record = next()
            case "--keep": c.keep = true
            case "--no-wallpaper": c.wallpaper = false
            case "--no-lights-out": c.lightsOut = false
            case "--no-sound": c.sound = false
            case "--no-blink": c.blink = false
            case "--max-yaw": c.maxYaw = Double(next() ?? "") ?? c.maxYaw
            case "--max-pitch": c.maxPitch = Double(next() ?? "") ?? c.maxPitch
            case "--max-turn": c.maxTurn = Double(next() ?? "") ?? c.maxTurn
            case "--eyes-closed": c.eyesClosed = Double(next() ?? "") ?? c.eyesClosed
            default:
                FileHandle.standardError.write("unknown option: \(args[i])\n".data(using: .utf8)!)
                cmd = .help
            }
            i += 1
        }
        return (c, cmd)
    }

    static let usage = """
    behindyou — it only moves when you aren't looking.

    USAGE
      behindyou [options]          start the haunting (opt-in, fully reversible)
      behindyou --calibrate        30-second guided check of what counts as "looking away"
      behindyou --lights-on        restore wallpaper + appearance from a run that didn't end cleanly
      behindyou --list-cameras     list cameras
      behindyou --preview [photo]  render the figure (and a haunted copy of photo) to ./preview

    OPTIONS
      --stages N        look-aways before the finale (default 7)
      --fast            short demo run (5 stages, quicker triggers)
      --camera NAME     pick a camera by (partial) name
      --keep            keep the haunted photos (saved to ~/Pictures/BehindYou)
      --pip             show your webcam in a corner (for recording a demo)
      --record FILE     record the screen + sound + mic to FILE while it runs
      --debug           show what the watcher sees
      --no-wallpaper --no-lights-out --no-sound --no-blink
      --max-yaw R --max-pitch R --max-turn X --eyes-closed F   gaze thresholds

    Ctrl-C, or the 🕯 menu-bar item, turns the lights back on and puts everything back.
    """
}
