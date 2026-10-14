import SwiftUI

/// Short status pill for queue operations. The shell, Now Playing and the queue sheet each cover
/// the others, so each one shows it itself.
struct QueueNoticeBanner: ViewModifier {
    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notice = self.environment.player.queueNotice {
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(duration: 0.35), value: self.environment.player.queueNotice)
    }
}

extension View {
    func queueNoticeBanner() -> some View { self.modifier(QueueNoticeBanner()) }
}
