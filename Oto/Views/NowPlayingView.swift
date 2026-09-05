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
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).frame(width: 48, height: 48)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .disabled(player.isLoading)
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
                        Text(player.currentTrack?.albumTitle ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
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
                        Button { player.toggle() } label: {
                            Group {
                                if player.isLoading { ProgressView().controlSize(.large) }
                                else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44)) }
                            }
                            .frame(width: 64, height: 64)
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        .accessibilityIdentifier("now-playing-toggle")
                        .disabled(player.isLoading)
                        Button { player.next() } label: { Image(systemName: "forward.fill").font(.title).frame(width: 52, height: 60) }
                            .accessibilityLabel("Next Song").disabled(!player.hasNext)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .onChange(of: player.currentTrack?.id) { _, _ in isSeeking = false; seekPosition = 0 }
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
