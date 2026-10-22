import ScreenCaptureKit

/// Records the screen, the haunting's sound and your microphone to a movie — for the demo video.
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var finished: (() -> Void)?

    func start(to url: URL, display: CGDirectDisplayID, _ done: @escaping (String?) -> Void) {
        try? FileManager.default.removeItem(at: url)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content, let screen = content.displays.first(where: { $0.displayID == display }) ?? content.displays.first
            else {
                done("can't record the screen: \(error?.localizedDescription ?? "no display") — allow Screen Recording in System Settings")
                return
            }
            let config = SCStreamConfiguration()
            config.width = screen.width
            config.height = screen.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = true
            config.capturesAudio = true
            config.captureMicrophone = true

            let stream = SCStream(filter: SCContentFilter(display: screen, excludingWindows: []),
                                  configuration: config, delegate: self)
            let rc = SCRecordingOutputConfiguration()
            rc.outputURL = url
            rc.outputFileType = .mov
            rc.videoCodecType = .hevc
            do {
                try stream.addRecordingOutput(SCRecordingOutput(configuration: rc, delegate: self))
            } catch {
                done("can't record: \(error.localizedDescription)")
                return
            }
            self.stream = stream
            stream.startCapture { err in
                DispatchQueue.main.async {
                    if err == nil { log("recording to \(url.path)") }
                    done(err?.localizedDescription)
                }
            }
        }
    }

    /// Stops and waits for the file to be finished.
    func stop(_ done: @escaping () -> Void) {
        guard let stream else { return done() }
        finished = done
        stream.stopCapture { _ in }
        // Don't hang forever if the delegate never fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.finish() }
    }

    private func finish() {
        DispatchQueue.main.async {
            let f = self.finished
            self.finished = nil
            f?()
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finish() }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        log("recording failed: \(error.localizedDescription)")
        finish()
    }
}
