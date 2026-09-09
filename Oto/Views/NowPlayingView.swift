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
                        MarqueeText(text: player.currentTrack?.title ?? "", style: .subheadline, weight: .medium)
                        MarqueeText(text: player.currentTrack?.artist ?? "", style: .caption1, color: .secondaryLabel)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing: \(player.currentTrack?.title ?? "")")
            .accessibilityIdentifier("mini-player")
            Button { player.toggle() } label: {
                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold)).frame(width: 48, height: 48)
            }
            .accessibilityLabel(player.wantsPlayback ? "Pause" : "Play")
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
    @State private var showingQueue = false
    @State private var queueEditMode: EditMode = .inactive

    var body: some View {
        GeometryReader { geometry in
            if showingQueue {
                queueView(compact: geometry.size.width > geometry.size.height)
                    .dynamicTypeSize(...(geometry.size.width > geometry.size.height ? DynamicTypeSize.xxxLarge : .accessibility5))
            } else if geometry.size.width > geometry.size.height {
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
        .modifier(ArtworkTheme(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory))
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape) { dismiss() }
        .onChange(of: player.currentEntryID) { _, _ in isSeeking = false; seekPosition = 0 }
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
            accessories(compact: compact)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadata: some View {
        VStack(spacing: 7) {
            MarqueeText(text: player.currentTrack?.title ?? "Nothing Playing", alignment: .center, style: .title2, weight: .bold)
                .accessibilityIdentifier("now-playing-title")
            MarqueeText(text: player.currentTrack?.artist ?? "", alignment: .center, style: .title3, color: .secondaryLabel)
        }
        .multilineTextAlignment(.center)
    }

    private var seeking: some View {
        let position = isSeeking ? seekPosition : player.elapsed
        return VStack(spacing: 3) {
            PlaybackSlider(player: player, active: scenePhase == .active, preview: $seekPosition, seeking: $isSeeking)
                .frame(height: 44)
            HStack {
                Text(MusicTime.clock(position))
                Spacer()
                Text("−" + MusicTime.clock(player.duration - position))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func transport(compact: Bool) -> some View {
        HStack(spacing: 0) {
            modeButton(symbol: "shuffle", selected: player.isShuffled, label: "Shuffle", value: player.isShuffled ? "On" : "Off") {
                player.setShuffle(!player.isShuffled)
            }
            .accessibilityIdentifier("shuffle-toggle")
            Spacer(minLength: 0)
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26)).frame(width: 48, height: 56)
            }
            .accessibilityLabel("Previous Song")
            Spacer(minLength: 0)
            Button { player.toggle() } label: {
                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 34 : 42))
                    .frame(width: 60, height: compact ? 56 : 64)
            }
            .accessibilityLabel(player.wantsPlayback ? "Pause" : "Play")
            .accessibilityIdentifier("now-playing-toggle")
            Spacer(minLength: 0)
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26)).frame(width: 48, height: 56)
            }
            .accessibilityLabel("Next Song").disabled(!player.hasNext)
            .accessibilityIdentifier("now-playing-next")
            Spacer(minLength: 0)
            modeButton(symbol: player.repeatMode.symbol, selected: player.repeatMode != .off,
                       label: "Repeat", value: player.repeatMode.label) {
                player.setRepeat(player.repeatMode.next)
            }
            .accessibilityIdentifier("repeat-toggle")
        }
        .buttonStyle(.plain)
    }

    private func modeButton(symbol: String, selected: Bool, label: String, value: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 36, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9).fill(.tint).opacity(selected ? 0.15 : 0)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessories(compact: Bool) -> some View {
        HStack(alignment: .top) {
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            Spacer()
            VStack(spacing: 0) {
                RoutePicker().frame(width: 52, height: 44)
                if !compact {
                    Text(player.currentTrack?.fileExtension ?? "")
                        .font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            modeButton(symbol: "list.bullet", selected: showingQueue, label: "Queue", value: showingQueue ? "Visible" : "Hidden") {
                showingQueue.toggle()
                queueEditMode = .inactive
            }
            .accessibilityIdentifier("queue-toggle")
        }
    }

    private func queueView(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 12) {
            HStack(spacing: 12) {
                ArtworkView(key: player.currentTrack?.artworkKey, directory: player.artworkDirectory, size: compact ? 40 : 56)
                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: player.currentTrack?.title ?? "Nothing Playing", style: .headline, weight: .semibold)
                    MarqueeText(text: player.currentTrack?.artist ?? "", style: .subheadline, color: .secondaryLabel)
                }
            }
            .padding(.horizontal, 24)
            HStack(spacing: 16) {
                Text("Playing Next").font(.headline)
                Spacer()
                if !player.upcoming.isEmpty {
                    Button("Clear") { player.clearUpcoming(); queueEditMode = .inactive }
                        .accessibilityIdentifier("clear-queue")
                    Button(queueEditMode.isEditing ? "Done" : "Edit") {
                        withAnimation { queueEditMode = queueEditMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("edit-queue")
                }
            }
            .padding(.horizontal, 24)
            if player.upcoming.isEmpty {
                Text("Nothing queued")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(player.upcoming) { entry in
                        Button { player.jump(to: entry.id) } label: {
                            HStack(spacing: 12) {
                                ArtworkView(key: entry.track.artworkKey, directory: player.artworkDirectory, size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.track.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text(entry.track.artist).font(.caption).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("queued-" + entry.track.title)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { player.removeUpcoming(entry.id) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: "Remove from Queue") { player.removeUpcoming(entry.id) }
                    }
                    .onMove { player.moveUpcoming(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .environment(\.editMode, $queueEditMode)
                .accessibilityIdentifier("upcoming-queue")
            }
            VStack(spacing: compact ? 0 : 8) {
                if !compact { seeking }
                transport(compact: compact)
                accessories(compact: compact)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
        }
        .padding(.top, 16)
        .padding(.bottom, compact ? 8 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
