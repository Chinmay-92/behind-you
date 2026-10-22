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
| **Takes your cursor** | Your cursor ends up where its eyes are. |
| **Whispers** | Through the macOS Whisper voice: *"i see you"*, *"closer"*, *"behind you"*. |
| **Messages you** | A real notification: *turn around.* |
| **Heartbeat** | A synthesized pulse that speeds up every stage. |
| **Photographs you** | It takes a webcam frame every time you look away. Vision person segmentation puts the figure *behind* you in the frame, and closer in each photo. |
| **The finale** | Look back at the end and the last photo fills the screen with a scream. Then: *"you looked away 7 times. I was there every time."* and every photo, in order. |

Gaze detection runs on Apple Vision face landmarks (head yaw/pitch, nose offset, and eye openness against your own baseline). It's all on-device, and nothing leaves the machine.

## Harmless by design

- **Opt-in.** Nothing happens until you run it, and the banner lists everything it will do.
- **Reversible.** Your original wallpaper (per display, with its scaling options) is written to a journal *before* anything is changed. It's restored when the run ends, on Ctrl-C, from the 🕯 menu-bar item, and even after a crash (the next launch, or `behindyou --exorcise`).
- **Private.** Photos are held in memory only and are gone when it exits. They're saved to `~/Pictures/BehindYou` only if you pass `--keep`.
- **Yours only.** It touches nothing outside your own user session, deletes nothing, and never uses the network.

## Run it

Requires macOS 14+ and Xcode command-line tools.

```sh
swift build -c release
.build/release/behindyou            # the full haunting (7 look-aways)
.build/release/behindyou --fast     # 5 look-aways, quicker — good for a demo
.build/release/behindyou --debug    # shows what the watcher sees (yaw, eyes, state)
```

The first run asks for camera access (granted to your terminal). For a standalone app with its own camera prompt, run `./scripts/bundle.sh`.

```
--stages N        look-aways before the finale (default 7)
--fast            short demo run
--camera NAME     pick a camera by (partial) name   (--list-cameras to see them)
--no-camera       no webcam: "looking away" = not touching keyboard/mouse
--keep            keep the haunted photos
--no-wallpaper --no-voice --no-cursor --no-notify --no-sound --no-blink
--exorcise        restore everything from a run that didn't end cleanly
--preview [img]   render the figure, a haunted wallpaper, and a haunted copy of img to ./preview
```

## How it's built

Swift with no dependencies: AVFoundation, Vision, Core Image, Core Animation, AppKit. All art and sound are generated at runtime: the figure is procedural Core Graphics with noise displacement, and the heartbeat, sting and scream are synthesized PCM.

```
Watcher.swift   webcam + Vision → "are you looking?" (debounced, blink-tolerant)
Haunter.swift   the rules: stages, what happens at each, photo capture, finale
Overlay.swift   click-through window over your desktop; jumpscare + gallery
GhostArt.swift  the figure; segmentation-based "behind you" photo compositing
Journal.swift   write-before-touch restore journal; wallpaper haunting
Sound.swift     synthesized heartbeat / sting / scream; Whisper voice
```

## Demo video

1. Start `behindyou --fast --debug` and keep working normally. Show the HUD reading *WATCHING*.
2. Turn to talk to the camera or a friend. When you turn back, it has appeared in the corner.
3. Look away a few more times. Each time it's closer, your wallpaper has changed, your cursor has moved, and it whispers.
4. Look away one last time. Hear *"behind you."* Look back.
5. Jumpscare, then the gallery of you not looking.
6. End on the wallpaper snapping back to normal.

MIT licensed.
