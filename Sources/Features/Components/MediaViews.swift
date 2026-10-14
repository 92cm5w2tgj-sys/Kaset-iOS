import SwiftUI

/// Square (or circular) artwork card used in shelves.
struct MediaCard: View {
    @Environment(AppEnvironment.self) private var environment

    let entity: MediaEntity
    var width: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: self.entity.thumbnailURL)
                .frame(width: self.width, height: self.width)
                .clipShape(self.entity.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                .overlay {
                    if self.entity.isCircular {
                        Circle().strokeBorder(.primary.opacity(0.08))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08))
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .overlay(alignment: .bottomTrailing) { self.quickPlay }
            Text(self.entity.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.top, 2)
            if let subtitle = self.entity.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: self.width, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    /// Playlists and albums open their page on tap; this plays them without opening it.
    @ViewBuilder
    private var quickPlay: some View {
        switch self.entity.target {
        case .playlist, .album:
            Button {
                Haptics.tap()
                self.environment.playEntity(self.entity)
            } label: {
                Image(systemName: "play.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Play \(self.entity.title)")
        default:
            EmptyView()
        }
    }
}

/// List row used by search results.
struct MediaRow: View {
    let entity: MediaEntity

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: self.entity.thumbnailURL)
                .frame(width: 56, height: 56)
                .clipShape(self.entity.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            VStack(alignment: .leading, spacing: 2) {
                Text(self.entity.title).font(.body).lineLimit(1)
                if let subtitle = self.entity.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Wraps content so a tap and the long-press menu send commands to the web player.
/// Songs and playlists play; albums and artists open their detail screen (K8).
struct MediaActions<Content: View>: View {
    @Environment(AppEnvironment.self) private var environment

    let entity: MediaEntity
    @ViewBuilder var content: Content

    var body: some View {
        switch self.entity.target {
        case .song:
            Button(action: self.play) { self.content }
                .buttonStyle(.plain)
                .contextMenu { self.menu }
        case .playlist, .album:
            // Like the macOS app: the page opens; playing is an explicit action.
            NavigationLink(value: self.entity) { self.content }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Play", systemImage: "play.fill") { self.environment.playEntity(self.entity) }
                }
        case .artist, .mood:
            NavigationLink(value: self.entity) { self.content }
                .buttonStyle(.plain)
        case .unsupported:
            self.content.opacity(0.5)
        }
    }

    private func play() {
        let player = self.environment.player
        switch self.entity.target {
        case let .song(videoId):
            player.play(videoId: videoId, playlistId: "RDAMVM\(videoId)")
        default:
            self.environment.playEntity(self.entity)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Play", systemImage: "play.fill", action: self.play)
        if let videoId = self.entity.videoId {
            Button("Play Next", systemImage: "text.insert") {
                self.environment.player.playNext(videoId: videoId)
            }
            Button("Add to Queue", systemImage: "text.append") {
                self.environment.player.addToQueue(videoId: videoId)
            }
        }
    }
}

/// Inline error with a retry action.
struct LoadFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(self.message)
        } actions: {
            Button("Try Again", action: self.retry)
        }
    }
}
