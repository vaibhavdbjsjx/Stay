import AVKit
import SwiftUI

/// Share progress cards and the Day 1 vs Day N video.
struct ShareStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var dog: Dog
    var highlight: Milestone?

    @State private var mode = 0
    @State private var style: ShareCardStyle = .beforeAfter
    @State private var cardImage: UIImage?
    @State private var videoURL: URL?
    @State private var videoProgress: Double?
    @State private var videoError: String?

    var body: some View {
        let story = ShareStory.make(dog: dog, model: model, highlight: highlight)
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Format", selection: $mode) {
                        Text("Card").tag(0)
                        Text("Video").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 {
                        cards(story)
                    } else {
                        video(story)
                    }
                }
                .padding(20)
            }
            .stayBackground()
            .navigationTitle("Share \(dog.name)'s progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                if highlight != nil { style = .milestone }
            }
        }
    }

    @ViewBuilder
    private func cards(_ story: ShareStory) -> some View {
        TabView(selection: $style) {
            ForEach(ShareCardStyle.allCases) { cardStyle in
                ShareCardView(story: story, style: cardStyle)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                    .padding(.vertical, 10)
                    .tag(cardStyle)
                    .accessibilityLabel(Text("\(cardStyle.title) card preview"))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: ShareCardView.size.height + 50)

        Text(style.title).font(StayFont.headline)

        if let image = cardImage {
            ShareLink(
                item: Image(uiImage: image),
                subject: Text("\(dog.name)'s progress"),
                message: Text("\(dog.name) is learning to stay home alone calmly with Stay."),
                preview: SharePreview(Text("\(dog.name)'s progress"), image: Image(uiImage: image))
            ) {
                Label("Share card", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.stayPrimary(StayPalette.apricot))
        }
        Text("Cards are made on your phone. Share to Instagram, Messages, or save to Photos.")
            .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
            .task(id: style) {
                cardImage = nil
                cardImage = ShareCardRenderer.render(story, style: style)
            }
    }

    @ViewBuilder
    private func video(_ story: ShareStory) -> some View {
        if let videoURL {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            ShareLink(item: videoURL, subject: Text("\(dog.name)'s progress")) {
                Label("Share video", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.stayPrimary(StayPalette.apricot))
            Button("Make it again") { self.videoURL = nil }.font(StayFont.callout)
        } else {
            ProgressVideoFrame(story: story, t: 0.6)
                .frame(width: 216, height: 384)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                .accessibilityHidden(true)
            Text("A 9-second vertical video of \(dog.name)'s journey from Day 1 to today, ready for Reels, TikTok and Stories.")
                .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
            if let videoProgress {
                VStack(spacing: 8) {
                    ProgressView(value: videoProgress).tint(StayPalette.apricot)
                    Text("Making your video…").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                }
            } else {
                Button {
                    makeVideo(story)
                } label: {
                    Label("Make video", systemImage: "film.stack")
                }
                .buttonStyle(.stayPrimary)
            }
            if let videoError {
                Text(videoError).font(StayFont.caption).foregroundStyle(StayPalette.alert)
            }
        }
    }

    private func makeVideo(_ story: ShareStory) {
        videoProgress = 0
        videoError = nil
        Task {
            do {
                let url = try await ProgressVideoMaker.make(story: story) { videoProgress = $0 }
                videoURL = url
                Haptics.success()
            } catch {
                videoError = String(localized: "The video couldn't be made. Please try again.")
            }
            videoProgress = nil
        }
    }
}
