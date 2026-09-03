import AVKit
import SwiftUI

/// A look you filmed, playing where its photograph would be. It loops, because a
/// four-second clip you have to restart by hand is a photograph with extra steps.
struct Player: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                p.actionAtItemEnd = .none      // .none, or the loop notification never arrives
                player = p
                p.play()
            }
            .onDisappear { player?.pause(); player = nil }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
    }
}

/// The tell that a card moves. Top trailing, clear of the name plate along the bottom.
struct PlayBadge: View {
    let side: CGFloat

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: side * 0.36))
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .background(Circle().fill(.black.opacity(0.30)))
                    .padding(10)
            }
            Spacer()
        }
    }
}

/// The still that stands in for a clip — in the pile, in the grid, in the share sheet.
enum Poster {
    /// A little way in, not frame zero: the chrome is still fading out when the
    /// recording starts, and a poster with half a shutter button in it looks broken.
    static func frame(_ url: URL, at seconds: Double = 0.4) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
