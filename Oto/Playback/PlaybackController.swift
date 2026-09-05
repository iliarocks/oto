import AVFoundation
import MediaPlayer
import Observation
import UIKit

// The loader transfers exclusive ownership to the main actor after preparing.
// No audio player is accessed concurrently across actors.
private final class PreparedAudio: @unchecked Sendable {
    let player: AVAudioPlayer
    let access: FolderAccess
    init(player: AVAudioPlayer, access: FolderAccess) { self.player = player; self.access = access }
}

private actor PlaybackLoader {
    func load(track: Track, bookmark: Data) async throws -> PreparedAudio {
        let access = try FolderAccess(bookmark: bookmark)
        let url = try MusicPath.resolve(track.relativePath, in: access.url)
        // Keep the scope alive across the read without sharing the player itself.
        let prepared = try await CoordinatedRead.perform(at: url) { readable in
            let player = try AVAudioPlayer(contentsOf: readable)
            guard player.prepareToPlay() else { throw LibraryError.inaccessibleFolder }
            return PreparedPlayer(player: player)
        }
        try Task.checkCancellation()
        return PreparedAudio(player: prepared.player, access: access)
    }
}

private final class PreparedPlayer: @unchecked Sendable {
    let player: AVAudioPlayer
    init(player: AVAudioPlayer) { self.player = player }
}

private actor AudioSessionController {
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
    }
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor @Observable final class PlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var currentTrack: Track?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?
    private(set) var queue: [Track] = []
    private(set) var currentIndex = 0
    var hasNext: Bool { currentIndex + 1 < queue.count }
    var hasPrevious: Bool { currentTrack != nil }
    let artworkDirectory: URL

    @ObservationIgnored private var audio: PreparedAudio?
    @ObservationIgnored private let loader = PlaybackLoader()
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private var playRequestID = UUID()
    @ObservationIgnored private var bookmark: Data?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?

    init(artworkDirectory: URL) {
        self.artworkDirectory = artworkDirectory
        super.init()
        configureRemoteCommands()
        observeSession()
    }

    func play(_ tracks: [Track], startingAt track: Track? = nil, bookmark: Data) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        self.bookmark = bookmark
        currentIndex = track.flatMap { selected in tracks.firstIndex { $0.id == selected.id } } ?? 0
        loadCurrent()
    }

    func toggle() {
        if isPlaying || (isLoading && wantsPlayback) { pause() }
        else { resume() }
    }

    func pause() {
        playRequestID = UUID()
        wantsPlayback = false
        resumeAfterInterruption = false
        audio?.player.pause()
        isPlaying = false
        updateTime()
        timer?.invalidate()
        timer = nil
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        wantsPlayback = true
        if isLoading { return }
        guard let audio else { loadCurrent(); return }
        let request = UUID()
        playRequestID = request
        Task {
            do {
                try await session.activate()
                guard playRequestID == request, wantsPlayback, self.audio === audio else { return }
                if elapsed >= duration - 0.05 { audio.player.currentTime = 0 }
                guard audio.player.play() else { throw LibraryError.inaccessibleFolder }
                isPlaying = true
                updateTime()
                startTimer()
                updateNowPlaying()
            } catch {
                guard playRequestID == request else { return }
                fail("Couldn't start playback. \(error.localizedDescription)")
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let audio, seconds.isFinite else { return }
        audio.player.currentTime = min(max(seconds, 0), max(0, audio.player.duration - 0.01))
        updateTime()
        updateNowPlaying()
    }

    func next() {
        guard hasNext else { return }
        let autoplay = wantsPlayback
        currentIndex += 1
        loadCurrent(autoplay: autoplay)
    }

    func previous() {
        if elapsed > 3 || currentIndex == 0 { seek(to: 0) }
        else {
            let autoplay = wantsPlayback
            currentIndex -= 1
            loadCurrent(autoplay: autoplay)
        }
    }

    func stop() {
        loadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        pause()
        audio?.player.stop()
        audio = nil
        currentTrack = nil
        queue = []
        bookmark = nil
        isLoading = false
        elapsed = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        Task { await session.deactivate() }
    }

    func cancelLoading() {
        guard isLoading else { return }
        loadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        pause()
        // Keep the selected song visible so Play is a clear retry action.
    }

    private func loadCurrent(autoplay: Bool = true) {
        guard queue.indices.contains(currentIndex), let bookmark else { return }
        loadTask?.cancel()
        pause()
        audio?.player.stop()
        audio = nil
        let track = queue[currentIndex]
        currentTrack = track
        elapsed = 0
        duration = track.duration
        isLoading = true
        wantsPlayback = autoplay
        nowPlayingArtwork = nil
        if let key = track.artworkKey,
           let image = UIImage(contentsOfFile: artworkDirectory.appendingPathComponent(key).path) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        updateNowPlaying()
        let id = UUID()
        loadID = id
        loadTask = Task {
            do {
                let prepared = try await loader.load(track: track, bookmark: bookmark)
                guard !Task.isCancelled, loadID == id else { return }
                audio = prepared
                prepared.player.delegate = self
                duration = prepared.player.duration
                isLoading = false
                if wantsPlayback { resume() }
                else { updateNowPlaying() }
            } catch {
                guard !Task.isCancelled, loadID == id else { return }
                isLoading = false
                fail("Couldn't open “\(track.title)”. Check that the music folder is available and the song is downloaded in Files, then try again.")
            }
        }
    }

    private func fail(_ message: String) {
        pause()
        errorMessage = message
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateTime() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateTime() {
        if let audio { elapsed = audio.player.currentTime }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audio?.player === player else { return }
            let shouldContinue = self.wantsPlayback
            self.pause()
            self.elapsed = self.duration
            if flag && shouldContinue && self.hasNext {
                self.currentIndex += 1
                self.loadCurrent()
            }
            else if !flag { self.fail("Playback stopped because this audio file could not be decoded.") }
            else { self.updateNowPlaying() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.audio?.player === player else { return }
            self.audio = nil
            self.fail("This audio file couldn't be decoded. Try the next song or check the original file.")
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PlaybackController) -> Void) {
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in if let self { action(self) } }
                return .success
            }
            remoteTargets.append((command, token))
        }
        register(center.playCommand) { $0.resume() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, token))
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = hasNext
        commands.previousTrackCommand.isEnabled = hasPrevious
        commands.changePlaybackPositionCommand.isEnabled = audio != nil && !isLoading
        commands.playCommand.isEnabled = currentTrack != nil
        commands.pauseCommand.isEnabled = currentTrack != nil
        commands.togglePlayPauseCommand.isEnabled = currentTrack != nil
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork = nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func observeSession() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    let shouldResume = self.wantsPlayback
                    self.pause()
                    self.resumeAfterInterruption = shouldResume
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.resume() }
                    self.resumeAfterInterruption = false
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadID = UUID()
                self.loadTask?.cancel()
                self.isLoading = false
                self.audio = nil
                self.fail("The audio system restarted. Tap Play to continue.")
            }
        })
    }

    isolated deinit {
        timer?.invalidate()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
}
