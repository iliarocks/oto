import AVKit
import SwiftUI

struct PlayerBar: ViewModifier {
    // Apply to each screen's content, inside NavigationStack, so its List
    // receives the bar's safe-area inset when scrolling to the final row.
    let player: PlaybackController
    let open: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { bar }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
    }

    @ViewBuilder private var bar: some View {
        if player.currentTrack != nil {
            MiniPlayer(player: player, open: open)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    LinearGradient(stops: [
                        .init(color: Color(uiColor: .systemBackground).opacity(0), location: 0),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.45), location: 0.55),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.9), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -24)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }
}

struct MiniPlayer: View {
    let player: PlaybackController
    let open: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArtworkView(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        MarqueeText(text: player.currentTrack?.title ?? "").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        MarqueeText(text: player.isLoading ? "Opening song…" : player.currentTrack?.artist ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing: \(player.currentTrack?.title ?? "")")
            .accessibilityIdentifier("mini-player")
            Button { if player.isLoading { player.cancelLoading() } else { player.toggle() } } label: {
                Image(systemName: player.isLoading ? "xmark" : player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold)).frame(width: 48, height: 48)
            }
            .accessibilityLabel(player.isLoading ? "Cancel Loading" : player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 48)
            }
            .accessibilityLabel("Next Song")
            .disabled(!player.hasNext)
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .modifier(PlayerGlass())
    }
}

private struct PlayerGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct NowPlayingView: View {
    let player: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var seekPosition: Double = 0
    @State private var isSeeking = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 24) {
                        artwork.frame(width: min(220, geometry.size.height - 24))
                        details(compact: true)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 20) {
                        artwork.frame(maxWidth: 360, maxHeight: .infinity)
                            .layoutPriority(-1)
                        details(compact: false)
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
        }
        .modifier(ArtworkTheme(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory))
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape) { dismiss() }
        .onChange(of: player.currentTrack?.id) { _, _ in isSeeking = false; seekPosition = 0 }
        .alert("Couldn't Play", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            if player.currentTrack != nil {
                Button("Try Again") { player.errorMessage = nil; player.resume() }
            }
            Button("Cancel", role: .cancel) { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private var artwork: some View {
        ArtworkView(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory)
    }

    private func details(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 22) {
            metadata
            seeking
            transport(compact: compact)
            if !compact {
                VStack(spacing: 7) {
                    RoutePicker().frame(width: 52, height: 44)
                    Text(player.currentTrack?.fileExtension ?? "")
                        .font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadata: some View {
        VStack(spacing: 7) {
            MarqueeText(text: player.currentTrack?.title ?? "Nothing Playing", alignment: .center).font(.title2.bold())
                .accessibilityIdentifier("now-playing-title")
            MarqueeText(text: player.currentTrack?.artist ?? "", alignment: .center).font(.title3).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var seeking: some View {
        TimelineView(.animation(paused: !player.isPlaying || scenePhase != .active)) { _ in
            let position = isSeeking ? seekPosition : player.preciseElapsed
            VStack(spacing: 3) {
                Slider(value: Binding(get: { position }, set: { seekPosition = $0 }),
                       in: 0...max(player.duration, 1), onEditingChanged: { editing in
                    if editing { seekPosition = player.preciseElapsed }
                    isSeeking = editing
                    if !editing { player.seek(to: seekPosition) }
                })
                .disabled(player.isLoading)
                .accessibilityLabel("Playback Position")
                .accessibilityValue(MusicTime.clock(position))
                .accessibilityIdentifier("playback-position")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(to: player.elapsed + 5)
                    case .decrement: player.seek(to: player.elapsed - 5)
                    @unknown default: break
                    }
                }
                HStack {
                    Text(MusicTime.clock(position))
                    Spacer()
                    Text("−" + MusicTime.clock(player.duration - position))
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func transport(compact: Bool) -> some View {
        HStack(spacing: compact ? 12 : 38) {
            Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 28)).frame(width: 52, height: 60) }
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
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 28)).frame(width: 52, height: 60) }
                .accessibilityLabel("Next Song").disabled(!player.hasNext)
                .accessibilityIdentifier("now-playing-next")
            if compact { RoutePicker().frame(width: 44, height: 44) }
        }
        .buttonStyle(.plain)
    }

}

private struct RoutePicker: UIViewRepresentable {
    @Environment(\.albumAccent) private var accent
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(accent)
        view.activeTintColor = UIColor(accent)
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(accent)
        view.activeTintColor = UIColor(accent)
    }
}
