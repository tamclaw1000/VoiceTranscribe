@preconcurrency import AVFoundation
import Combine
import Foundation

/// Plays the audio associated with the current transcript so the transcript pane can follow
/// the playhead (`AppModel.playbackFollowRowID`).
///
/// Load is lazy on purpose: a target is only opened when the user actually presses play, so a
/// finished recording sitting in the pane costs nothing until it is listened to.
///
/// Only finalized files can be opened. An in-progress recording is an `.m4a` whose `moov` atom
/// has not been written yet, and `AVAudioPlayer` refuses a header-only file — the same reason
/// `afinfo` rejects a truncated `.m4a`. Targets are therefore completed recordings and
/// imported files, never a file still being written.
@MainActor
final class AudioPlaybackService: NSObject, ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    /// A position requested before any file was open, applied once one is.
    private var pendingSeek: TimeInterval?

    /// How often the playhead is republished while playing. Fast enough that the transcript
    /// highlight tracks speech, slow enough not to re-render the pane dozens of times a second.
    private static let tickInterval: TimeInterval = 0.1

    deinit {
        ticker?.invalidate()
    }

    var hasAudio: Bool {
        player != nil
    }

    /// Opens `url` if it is not already open. Returns whether audio is ready to play.
    @discardableResult
    func load(url newURL: URL) -> Bool {
        if self.url == newURL, player != nil {
            return true
        }
        // `rewind()`, not `stop()`: opening a file must not discard a position that was queued
        // while nothing was open, and `stop()` deliberately does.
        rewind()
        self.url = newURL

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: newURL)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
            lastError = nil
            // Honour a position requested before the file was open, so the order of "open" and
            // "position this playhead" can never silently drop the position.
            if let pendingSeek {
                newPlayer.currentTime = min(max(pendingSeek, 0), max(newPlayer.duration, 0))
                currentTime = newPlayer.currentTime
                self.pendingSeek = nil
            }
            Trace.event("playback.loaded", [
                "file": newURL.lastPathComponent,
                "duration": String(format: "%.2f", newPlayer.duration)
            ])
            return true
        } catch {
            player = nil
            duration = 0
            currentTime = 0
            lastError = Self.friendlyError(for: error)
            Trace.event("playback.loadError", [
                "file": newURL.lastPathComponent,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    func play() {
        guard let player else {
            return
        }
        // Starting from the very end is indistinguishable from a dead play button, so rewind.
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
            currentTime = 0
        }
        guard player.play() else {
            lastError = "This audio could not be played."
            isPlaying = false
            return
        }
        isPlaying = true
        lastError = nil
        startTicker()
        Trace.event("playback.started", ["file": url?.lastPathComponent ?? "unknown"])
    }

    func pause() {
        guard let player else {
            return
        }
        player.pause()
        isPlaying = false
        stopTicker()
        syncPosition()
        Trace.event("playback.paused", [
            "file": url?.lastPathComponent ?? "unknown",
            "position": String(format: "%.2f", player.currentTime)
        ])
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Stops playback and rewinds, keeping the file loaded. An explicit stop also drops any
    /// position queued while nothing was open: stopping means "back to the start", not "start
    /// wherever the last scrub left off".
    func stop() {
        rewind()
        pendingSeek = nil
    }

    /// The rewind half of `stop()`, for callers that must not discard a pending position.
    private func rewind() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
    }

    /// Releases the loaded file entirely, for when the transcript it belonged to goes away.
    func unload() {
        stop()
        player = nil
        url = nil
        duration = 0
        lastError = nil
    }

    func seek(to offset: TimeInterval) {
        guard let player else {
            // A seek before any file is open is a request to play from there, not a no-op to
            // throw away. Discarding it is what made dragging the scrubber look like it did
            // nothing until the user had pressed play once.
            pendingSeek = max(offset, 0)
            return
        }
        let clamped = min(max(offset, 0), max(player.duration, 0))
        player.currentTime = clamped
        currentTime = clamped
    }

    private func startTicker() {
        guard ticker == nil else {
            return
        }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncPosition()
            }
        }
        // Common mode so the playhead keeps advancing while the user drags the scrubber.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func syncPosition() {
        guard let player else {
            return
        }
        let position = player.currentTime
        if abs(position - currentTime) > 0.001 {
            currentTime = position
        }
    }

    /// `AVAudioPlayer` also refuses a file it cannot decode (FLAC, for one), and the raw
    /// message ("The operation couldn't be completed") says nothing a user can act on.
    private static func friendlyError(for error: Error) -> String {
        let code = (error as NSError).code
        // AVFoundationErrorDomain -11828 / -39 are "unsupported format" / "corrupt file".
        if code == -11828 || code == -39 {
            return "This audio format cannot be played back here."
        }
        return "This audio could not be opened for playback."
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.stopTicker()
            self.currentTime = self.duration
            Trace.event("playback.finished", [
                "file": self.url?.lastPathComponent ?? "unknown",
                "success": flag ? "true" : "false"
            ])
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.stopTicker()
            self.lastError = Self.friendlyError(for: error ?? URLError(.unknown))
            Trace.event("playback.decodeError", [
                "file": self.url?.lastPathComponent ?? "unknown",
                "error": error?.localizedDescription ?? "unknown"
            ])
        }
    }
}
