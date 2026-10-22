import Foundation

enum Command {
    case haunt
    case exorcise
    case preview(photo: String?)
    case listCameras
    case help
}

struct Config {
    /// Number of look-aways before the finale.
    var stages = 7
    var useCamera = true
    var autopilot = false
    var autopilotPhoto: String?
    var cameraName: String?
    var debug = false
    var keep = false
    var wallpaper = true
    var voice = true
    var cursor = true
    var notifications = true
    var sound = true
    var blink = true
    /// How long you must be looking away before it moves.
    var minAway: TimeInterval = 0.5
    /// Idle seconds that count as "looking away" in --no-camera mode.
    var idleThreshold: TimeInterval = 4
    /// Calm period after launch before anything can happen.
    var grace: TimeInterval = 4

    static func parse(_ args: [String]) -> (Config, Command) {
        var c = Config()
        var cmd = Command.haunt
        var i = 0
        func next() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            switch args[i] {
            case "--exorcise", "--restore": cmd = .exorcise
            case "--preview":
                var photo: String?
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") { photo = next() }
                cmd = .preview(photo: photo)
            case "--list-cameras": cmd = .listCameras
            case "-h", "--help": cmd = .help
            case "--stages": c.stages = max(2, Int(next() ?? "") ?? c.stages)
            case "--fast":
                c.stages = 5
                c.minAway = 0.35
                c.grace = 2
            case "--camera": c.cameraName = next()
            case "--no-camera": c.useCamera = false
            case "--autopilot":
                c.autopilot = true
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") { c.autopilotPhoto = next() }
            case "--idle": c.idleThreshold = Double(next() ?? "") ?? c.idleThreshold
            case "--debug": c.debug = true
            case "--keep": c.keep = true
            case "--no-wallpaper": c.wallpaper = false
            case "--no-voice": c.voice = false
            case "--no-cursor": c.cursor = false
            case "--no-notify": c.notifications = false
            case "--no-sound": c.sound = false
            case "--no-blink": c.blink = false
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
      behindyou --exorcise         restore wallpaper + delete photos from a crashed run
      behindyou --list-cameras     list cameras
      behindyou --preview [photo]  render the ghost (and a haunted copy of photo) to ./preview

    OPTIONS
      --stages N        look-aways before the finale (default 7)
      --fast            short demo run (5 stages, quicker triggers)
      --camera NAME     pick a camera by (partial) name
      --no-camera       no webcam: "looking away" = not touching keyboard/mouse
      --idle SECONDS    idle threshold for --no-camera (default 4)
      --keep            keep the haunted photos (saved to ~/Pictures/BehindYou)
      --debug           show what the watcher sees
      --no-wallpaper --no-voice --no-cursor --no-notify --no-sound --no-blink

    Ctrl-C, or the 🕯 menu-bar item, exorcises everything immediately.
    """
}
