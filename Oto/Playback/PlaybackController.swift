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
    // Transport intent stays stable while preparing a song or activating audio.
    private(set) var wantsPlayback = false
    private(set) var isLoading = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?
    private(set) var playbackQueue = PlaybackQueue()
    var upcoming: [QueueEntry] { playbackQueue.upcoming }
    var currentEntryID: UUID? { playbackQueue.currentID }
    var repeatMode: RepeatMode { playbackQueue.repeatMode }
    var preciseElapsed: TimeInterval { audio?.player.currentTime ?? elapsed }
    var hasNext: Bool { playbackQueue.canAdvance }
    var hasPrevious: Bool { currentTrack != nil }
    let artworkDirectory: URL

    @ObservationIgnored private var audio: PreparedAudio?
    @ObservationIgnored private let loader = PlaybackLoader()
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private var playRequestID = UUID()
    @ObservationIgnored private var bookmark: Data?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var folderPath: String?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    private var playbackURL: URL { artworkDirectory.deletingLastPathComponent().appendingPathComponent("playback.json") }

    init(artworkDirectory: URL, library: LibrarySnapshot? = nil) {
        self.artworkDirectory = artworkDirectory
        super.init()
        configureRemoteCommands()
        observeSession()
        if let data = try? Data(contentsOf: playbackURL),
           let saved = try? JSONDecoder().decode(SavedPlayback.self, from: data), saved.queue.isValid {
            playbackQueue = saved.queue
            folderPath = saved.folderPath
            elapsed = saved.elapsed.isFinite ? max(0, saved.elapsed) : 0
            if let library { reconcile(with: library) }
            else { playbackQueue.clear(); elapsed = 0 }
        }
    }

    func play(_ tracks: [Track], startingAt track: Track? = nil, bookmark: Data) {
        guard !tracks.isEmpty else { return }
        playbackQueue.start(tracks, at: track)
        self.bookmark = bookmark
        folderPath = (try? FolderAccess(bookmark: bookmark))?.url.standardizedFileURL.path
        loadCurrent()
    }

    func enqueue(_ tracks: [Track], bookmark: Data) {
        guard !tracks.isEmpty else { return }
        if currentTrack == nil {
            self.bookmark = bookmark
            folderPath = (try? FolderAccess(bookmark: bookmark))?.url.standardizedFileURL.path
            playbackQueue.append(tracks)
            loadCurrent()
        } else {
            playbackQueue.append(tracks)
            queueChanged()
        }
    }

    func setRepeat(_ mode: RepeatMode) { playbackQueue.repeatMode = mode; queueChanged() }
    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        playbackQueue.move(from: offsets, to: destination); queueChanged()
    }
    func removeUpcoming(_ id: UUID) { playbackQueue.remove([id]); queueChanged() }
    func clearUpcoming() { playbackQueue.clearUpcoming(); queueChanged() }
    func jump(to id: UUID) {
        let autoplay = wantsPlayback
        if playbackQueue.jump(to: id) { loadCurrent(autoplay: autoplay) }
    }

    private func queueChanged() { updateNowPlaying(); checkpoint() }

    func checkpoint() {
        let saved = SavedPlayback(queue: playbackQueue, folderPath: folderPath, elapsed: preciseElapsed)
        do {
            try FileManager.default.createDirectory(at: playbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: playbackURL, options: .atomic)
            lastCheckpoint = Date()
        } catch {
            // Playback remains usable if the device cannot save restoration state.
            NSLog("Oto could not save playback state: %@", error.localizedDescription)
        }
    }

    func reconcile(with snapshot: LibrarySnapshot) {
        let newPath = (try? FolderAccess(bookmark: snapshot.bookmark))?.url.standardizedFileURL.path
        if let newPath, let folderPath, newPath != folderPath { stop(); return }
        let previousID = playbackQueue.currentID
        playbackQueue.reconcile(with: snapshot.tracks)
        bookmark = snapshot.bookmark
        folderPath = newPath ?? folderPath
        if playbackQueue.currentID != previousID {
            let replacement = playbackQueue.current
            loadID = UUID(); loadTask?.cancel(); loadTask = nil
            pause(persist: false)
            audio?.player.stop(); audio = nil; isLoading = false
            elapsed = 0
            currentTrack = replacement?.track
        } else { currentTrack = playbackQueue.current?.track }
        duration = currentTrack?.duration ?? 0
        elapsed = min(elapsed, duration)
        refreshArtwork()
        queueChanged()
    }

    func toggle() {
        if wantsPlayback { pause() }
        else { resume() }
    }

    func pause(persist: Bool = true) {
        playRequestID = UUID()
        wantsPlayback = false
        resumeAfterInterruption = false
        audio?.player.pause()
        isPlaying = false
        updateTime()
        timer?.invalidate()
        timer = nil
        updateNowPlaying()
        if persist { checkpoint() }
    }

    func resume() {
        guard currentTrack != nil else { return }
        wantsPlayback = true
        if isLoading { return }
        guard let audio else { loadCurrent(startPosition: elapsed); return }
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
        guard currentTrack != nil, !isLoading, seconds.isFinite else { return }
        elapsed = min(max(seconds, 0), max(0, duration - 0.01))
        audio?.player.currentTime = elapsed
        updateNowPlaying()
        checkpoint()
    }

    func next() {
        let autoplay = wantsPlayback
        guard playbackQueue.advance() else { return }
        loadCurrent(autoplay: autoplay)
    }

    func previous() {
        if preciseElapsed > 3 { seek(to: 0) }
        else {
            let autoplay = wantsPlayback
            if playbackQueue.previous() { loadCurrent(autoplay: autoplay) }
            else { seek(to: 0) }
        }
    }

    func stop() {
        loadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        pause(persist: false)
        audio?.player.stop()
        audio = nil
        currentTrack = nil
        playbackQueue.clear()
        bookmark = nil
        folderPath = nil
        isLoading = false
        elapsed = 0
        duration = 0
        updateNowPlaying()
        checkpoint()
        Task { await session.deactivate() }
    }

    private func loadCurrent(autoplay: Bool = true, startPosition: TimeInterval = 0) {
        guard let track = playbackQueue.current?.track, let bookmark else { return }
        loadTask?.cancel()
        pause(persist: false)
        audio?.player.stop()
        audio = nil
        currentTrack = track
        errorMessage = nil
        elapsed = startPosition
        duration = track.duration
        isLoading = true
        wantsPlayback = autoplay
        refreshArtwork()
        checkpoint()
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
                prepared.player.currentTime = min(max(startPosition, 0), max(0, duration - 0.01))
                elapsed = prepared.player.currentTime
                isLoading = false
                if wantsPlayback { resume() }
                else { updateNowPlaying() }
            } catch LibraryError.fileNotDownloaded {
                guard !Task.isCancelled, loadID == id else { return }
                isLoading = false
                fail("Download “\(track.title)” in Files first, then tap Play again.")
            } catch {
                guard !Task.isCancelled, loadID == id else { return }
                isLoading = false
                fail("Couldn't open “\(track.title)”. Check that the music folder is available and the song is downloaded in Files, then try again.")
            }
        }
    }

    private func refreshArtwork() {
        nowPlayingArtwork = nil
        if let key = currentTrack?.artworkKey,
           let image = UIImage(contentsOfFile: artworkDirectory.appendingPathComponent(key).path) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
    }

    private func fail(_ message: String) {
        pause()
        errorMessage = message
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateTime()
                if Date().timeIntervalSince(self.lastCheckpoint) >= 5 { self.checkpoint() }
            }
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
            if flag && shouldContinue && self.playbackQueue.advance(automatically: true) {
                self.loadCurrent()
            }
            else if !flag { self.fail("Playback stopped because this audio file could not be decoded.") }
            else { self.updateNowPlaying(); self.checkpoint() }
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
        let repeatToken = center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode = event.repeatType == .one ? .one : (event.repeatType == .all ? .all : .off)
            Task { @MainActor [weak self] in self?.setRepeat(mode) }
            return .success
        }
        remoteTargets.append((center.changeRepeatModeCommand, repeatToken))
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = hasNext
        commands.previousTrackCommand.isEnabled = hasPrevious
        commands.changePlaybackPositionCommand.isEnabled = currentTrack != nil && !isLoading
        commands.playCommand.isEnabled = currentTrack != nil
        commands.pauseCommand.isEnabled = currentTrack != nil
        commands.togglePlayPauseCommand.isEnabled = currentTrack != nil
        commands.changeShuffleModeCommand.isEnabled = false
        commands.changeShuffleModeCommand.currentShuffleType = .off
        commands.changeRepeatModeCommand.isEnabled = currentTrack != nil
        commands.changeRepeatModeCommand.currentRepeatType = repeatMode == .one ? .one : (repeatMode == .all ? .all : .off)
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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
