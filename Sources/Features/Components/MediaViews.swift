import SwiftUI

/// Square (or circular) artwork card used in shelves.
struct MediaCard: View {
    let entity: MediaEntity
    var width: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: self.entity.thumbnailURL)
                .frame(width: self.width, height: self.width)
                .clipShape(self.entity.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
            Text(self.entity.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if let subtitle = self.entity.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: self.width, alignment: .leading)
    }
}

/// List row used by search results.
struct MediaRow: View {
    let entity: MediaEntity

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: self.entity.thumbnailURL)
                .frame(width: 52, height: 52)
                .clipShape(self.entity.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
            VStack(alignment: .leading, spacing: 2) {
                Text(self.entity.title).lineLimit(1)
                if let subtitle = self.entity.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        case .song, .playlist:
            Button(action: self.play) { self.content }
                .buttonStyle(.plain)
                .contextMenu { self.menu }
        case .album, .artist:
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
        case let .playlist(id):
            player.play(videoId: nil, playlistId: MediaEntity.watchPlaylistId(id))
        default:
            break
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

/// Destination for albums and artists until the detail screens exist (K8).
struct EntityPlaceholderView: View {
    let entity: MediaEntity

    var body: some View {
        ContentUnavailableView(
            self.entity.title,
            systemImage: "square.stack",
            description: Text("\(self.entity.kindLabel) details arrive in a later step.")
        )
        .navigationTitle(self.entity.title)
        .navigationBarTitleDisplayMode(.inline)
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
