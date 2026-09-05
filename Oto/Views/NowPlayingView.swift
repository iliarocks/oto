import AVKit
import SwiftUI

struct MiniPlayer: View {
    let player: PlaybackController
    let open: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArtworkView(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.currentTrack?.title ?? "").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(player.isLoading ? "Opening song…" : player.currentTrack?.artist ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing: \(player.currentTrack?.title ?? "")")
            .accessibilityIdentifier("mini-player")
            Button { if player.isLoading { player.cancelLoading() } else { player.toggle() } } label: {
                Image(systemName: player.isLoading ? "xmark" : player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).frame(width: 48, height: 48)
            }
            .accessibilityLabel(player.isLoading ? "Cancel Loading" : player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title3).frame(width: 44, height: 48)
            }
            .accessibilityLabel("Next Song")
            .disabled(!player.hasNext)
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct NowPlayingView: View {
    let player: PlaybackController
    var showAlbum: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var seekPosition: Double = 0
    @State private var isSeeking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    ArtworkView(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory)
                        .frame(maxWidth: 360)
                    VStack(spacing: 7) {
                        Text(player.currentTrack?.title ?? "Nothing Playing").font(.title2.bold())
                        Text(player.currentTrack?.artist ?? "").font(.title3).foregroundStyle(.secondary)
                        if let showAlbum {
                            Button(action: showAlbum) {
                                HStack(spacing: 5) {
                                    Text(player.currentTrack?.albumTitle ?? "")
                                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                }
                            }
                            .font(.subheadline)
                            .accessibilityLabel("Go to album, \(player.currentTrack?.albumTitle ?? "")")
                            .accessibilityIdentifier("now-playing-album")
                        } else {
                            Text(player.currentTrack?.albumTitle ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    if player.isLoading {
                        HStack(spacing: 8) { ProgressView(); Text("Opening song…") }
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 3) {
                        Slider(value: Binding(get: { isSeeking ? seekPosition : player.elapsed }, set: { seekPosition = $0 }),
                               in: 0...max(player.duration, 1), onEditingChanged: { editing in
                            if editing { seekPosition = player.elapsed }
                            isSeeking = editing
                            if !editing { player.seek(to: seekPosition) }
                        })
                        .disabled(player.isLoading)
                        .accessibilityLabel("Playback Position")
                        .accessibilityValue(MusicTime.clock(isSeeking ? seekPosition : player.elapsed))
                        .accessibilityIdentifier("playback-position")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: player.seek(to: player.elapsed + 5)
                            case .decrement: player.seek(to: player.elapsed - 5)
                            @unknown default: break
                            }
                        }
                        HStack {
                            Text(MusicTime.clock(isSeeking ? seekPosition : player.elapsed))
                            Spacer()
                            Text("−" + MusicTime.clock(player.duration - (isSeeking ? seekPosition : player.elapsed)))
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 38) {
                        Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title).frame(width: 52, height: 60) }
                            .accessibilityLabel("Previous Song")
                        Button { if player.isLoading { player.cancelLoading() } else { player.toggle() } } label: {
                            Group {
                                if player.isLoading { Image(systemName: "xmark").font(.system(size: 36)) }
                                else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44)) }
                            }
                            .frame(width: 64, height: 64)
                        }
                        .accessibilityLabel(player.isLoading ? "Cancel Loading" : player.isPlaying ? "Pause" : "Play")
                        .accessibilityIdentifier("now-playing-toggle")
                        Button { player.next() } label: { Image(systemName: "forward.fill").font(.title).frame(width: 52, height: 60) }
                            .accessibilityLabel("Next Song").disabled(!player.hasNext)
                            .accessibilityIdentifier("now-playing-next")
                    }
                    .buttonStyle(.plain)
                    VStack(spacing: 7) {
                        RoutePicker().frame(width: 52, height: 44)
                        Text(player.currentTrack?.fileExtension ?? "")
                            .font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 30)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly).tint(.primary)
                }
            }
        }
        .onChange(of: player.currentTrack?.id) { _, _ in isSeeking = false; seekPosition = 0 }
        .alert("Couldn't Play", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            if player.currentTrack != nil {
                Button("Try Again") { player.errorMessage = nil; player.resume() }
            }
            Button("Cancel", role: .cancel) { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .label
        view.activeTintColor = .tintColor
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) { }
}
