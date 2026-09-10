import MediaPlayer
import UIKit

/// Owns the system media controls and their registrations. Playback state stays
/// in the controller; callbacks hold it weakly so registrations cannot retain it.
@MainActor
final class PlaybackSystemMedia {
    private weak var controller: PlaybackController?
    private let artworkDirectory: URL
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?

    init(controller: PlaybackController, artworkDirectory: URL) {
        self.controller = controller
        self.artworkDirectory = artworkDirectory
        configureRemoteCommands()
        update()
    }

    func refreshArtwork() {
        nowPlayingArtwork = nil
        if let key = controller?.currentTrack?.artworkKey,
           let image = UIImage(contentsOfFile: artworkDirectory.appendingPathComponent(key).path) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PlaybackController) -> Void) {
            let token = command.addTarget { [weak controller] _ in
                Task { @MainActor [weak controller] in if let controller { action(controller) } }
                return .success
            }
            remoteTargets.append((command, token))
        }
        register(center.playCommand) { $0.resume() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak controller] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak controller] in controller?.seek(to: position) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, token))
        let repeatToken = center.changeRepeatModeCommand.addTarget { [weak controller] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode = event.repeatType == .one ? .one : (event.repeatType == .all ? .all : .off)
            Task { @MainActor [weak controller] in controller?.setRepeat(mode) }
            return .success
        }
        remoteTargets.append((center.changeRepeatModeCommand, repeatToken))
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    func update() {
        guard let controller else { return }
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = controller.hasNext
        commands.previousTrackCommand.isEnabled = controller.hasPrevious
        commands.changePlaybackPositionCommand.isEnabled = controller.currentTrack != nil && !controller.isLoading
        commands.playCommand.isEnabled = controller.currentTrack != nil
        commands.pauseCommand.isEnabled = controller.currentTrack != nil
        commands.togglePlayPauseCommand.isEnabled = controller.currentTrack != nil
        commands.changeShuffleModeCommand.isEnabled = false
        commands.changeShuffleModeCommand.currentShuffleType = .off
        commands.changeRepeatModeCommand.isEnabled = controller.currentTrack != nil
        commands.changeRepeatModeCommand.currentRepeatType = controller.repeatMode == .one ? .one : (controller.repeatMode == .all ? .all : .off)
        guard let track = controller.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: controller.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: controller.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: controller.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork = nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    isolated deinit {
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
}
