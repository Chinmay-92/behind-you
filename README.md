# BEHIND YOU

**It only moves when you aren't looking.**

A macOS haunting that watches you through your own webcam. While your eyes are on the screen, nothing happens. The moment you look away (turn your head, check your phone, close your eyes) it gets closer, and something real on your Mac changes.

When you finally look back for the last time, it shows you a photo it took of you while you weren't looking. It's standing right behind you.

Built for Hackyard: *Haunted*.

## What it actually does

Every look-away moves it one stage closer. Over the run it:

| | |
|---|---|
| **Stands on your screen** | A click-through figure over your real windows. It's farther away at first, then closer each stage. It never moves while you're watching. |
| **Gets into your wallpaper** | Your actual wallpaper, on every display, gets drained of colour with a small figure standing far off in it. |
| **Turns the lights out** | Your Mac switches to Dark Mode while you aren't looking. |
| **Heartbeat** | A synthesized pulse that speeds up every stage, then stops when it's right behind you. |
| **Photographs you** | It takes a webcam frame every time you look away. Vision person segmentation puts the figure *behind* you in the frame, and closer in each photo. |
| **The finale** | Look back at the end and the last photo fills the screen with a scream. Then: *"you looked away 7 times. I was there every time."* and every photo, in order. |

Gaze detection runs on Apple Vision: continuous head yaw and pitch, the nose offset between your eyes, and eye openness. Webcams rarely sit dead-centre, so it learns *your* resting pose in the first seconds and measures every turn from there. It was tuned on real calibration runs (`--calibrate`): looking at the screen, turning, looking down at a phone and closing your eyes are each detected correctly 100% of the time once settled. It all runs on-device and nothing leaves the machine.

## Harmless by design

- **Opt-in.** Nothing happens until you run it, and the banner lists everything it will do.
- **Reversible.** Your original wallpaper (per display, with its scaling options) and your appearance are written to a journal *before* anything is changed. The lights come back on when the run ends, on Ctrl-C, from the 🕯 menu-bar item, and even after a crash (the next launch, or `behindyou --lights-on`).
- **Private.** Photos are held in memory only and are gone when it exits. They're saved to `~/Pictures/BehindYou` only if you pass `--keep`.
- **Yours only.** It touches nothing outside your own user session, deletes nothing, and never uses the network.

## Run it

Requires macOS 15+ and Xcode command-line tools.

```sh
swift build -c release
.build/release/behindyou            # the full haunting (7 look-aways)
.build/release/behindyou --fast     # 5 look-aways, quicker — good for a demo
.build/release/behindyou --debug    # shows what the watcher sees (yaw, eyes, state)
.build/release/behindyou --calibrate   # 35-second guided check of your camera setup
```

The first run asks for camera access (granted to your terminal). For a standalone app with its own camera prompt, run `./scripts/bundle.sh`.

```
--stages N        look-aways before the finale (default 7)
--fast            short demo run
--camera NAME     pick a camera by (partial) name   (--list-cameras to see them)
--keep            keep the haunted photos
--pip             show your webcam in a corner (for demo recordings)
--record FILE     record screen + sound + mic while it runs (ScreenCaptureKit)
--no-wallpaper --no-lights-out --no-sound --no-blink
--max-yaw --max-pitch --max-turn --eyes-closed   thresholds, relative to your resting pose
--lights-on       restore everything from a run that didn't end cleanly
--preview [img]   render the figure, a haunted wallpaper, and a haunted copy of img to ./preview
```

## How it's built

Swift with no dependencies: AVFoundation, Vision, Core Image, Core Animation, AppKit. All art and sound are generated at runtime: the figure is procedural Core Graphics with noise displacement, and the heartbeat, sting and scream are synthesized PCM.

```
Watcher.swift   webcam + Vision → "are you looking?" (baseline-relative, debounced)
Calibration.swift  guided calibration that prints what the watcher saw per phase
Recorder.swift  ScreenCaptureKit demo recorder
Haunter.swift   the rules: stages, what happens at each, photo capture, finale
Overlay.swift   click-through window over your desktop; jumpscare + gallery
GhostArt.swift  the figure; segmentation-based "behind you" photo compositing
Journal.swift   write-before-touch restore journal; wallpaper + lights-out haunting
Sound.swift     synthesized heartbeat / sting / scream
```

## Demo video

1. Run `behindyou --fast --pip --record demo.mov` and keep working normally. Your webcam is in the corner.
2. Turn away for a couple of seconds. When you turn back, it has appeared on your screen.
3. Look away a few more times. Each time it's closer, your wallpaper has changed, the lights have gone out, and the heartbeat is faster.
4. Look away one last time. The heartbeat stops. Look back.
5. Jumpscare, then the gallery of you not looking.
6. End on the lights coming back on and your wallpaper returning.

MIT licensed.
