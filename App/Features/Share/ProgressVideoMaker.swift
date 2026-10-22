@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Builds the "Day 1 vs Day N" vertical video (1080×1920, H.264) entirely on device.
@MainActor
enum ProgressVideoMaker {
    static let size = CGSize(width: 1080, height: 1920)
    static let fps: Int32 = 30
    static let duration: Double = 9

    enum VideoError: Error { case setup, write }

    static func make(story: ShareStory, progress: @escaping (Double) -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Stay-\(story.dogName.isEmpty ? "progress" : story.dogName)-progress.mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw VideoError.setup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoError.setup }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let t = Double(frame) / Double(totalFrames - 1)
            let renderer = ImageRenderer(content: ProgressVideoFrame(story: story, t: t).frame(width: size.width / 3, height: size.height / 3))
            renderer.scale = 3
            renderer.isOpaque = true
            guard let cgImage = renderer.cgImage, let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: cgImage, pool: pool) else { throw VideoError.write }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            if frame % 6 == 0 {
                progress(t)
                await Task.yield()
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoError.write }
        progress(1)
        return url
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

/// One frame of the progress video at time `t` (0…1). Designed at 360×640 points.
struct ProgressVideoFrame: View {
    var story: ShareStory
    var t: Double

    private let cream = Color(hex: 0xFBF3E6)
    private let apricot = Color(hex: 0xF2A477)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4F8070), Color(hex: 0x1F3A32)], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(RadialGradient(colors: [apricot.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 460, height: 460)
                .offset(x: CGFloat(cos(t * .pi * 2)) * 40, y: -170 + CGFloat(sin(t * .pi * 2)) * 30)
            content
                .padding(30)
        }
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var content: some View {
        switch t {
        case ..<0.18: intro(local(0, 0.18))
        case ..<0.42: dayOne(local(0.18, 0.42))
        case ..<0.74: growth(local(0.42, 0.74))
        default: outro(local(0.74, 1))
        }
    }

    private func local(_ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
    private func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private func fadeIn(_ p: Double, delay: Double = 0) -> Double { min(1, max(0, (p - delay) / 0.25)) }

    private func intro(_ p: Double) -> some View {
        VStack(spacing: 22) {
            photo(size: 170).scaleEffect(0.8 + 0.2 * ease(min(1, p * 1.6))).opacity(fadeIn(p))
            Text(story.dogName).font(.system(size: 44, weight: .semibold, design: .serif)).foregroundStyle(cream).opacity(fadeIn(p, delay: 0.15))
            Text("learning to stay home alone").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.8)).opacity(fadeIn(p, delay: 0.3))
        }
    }

    private func dayOne(_ p: Double) -> some View {
        VStack(spacing: 20) {
            Text("Day 1").font(.system(size: 22, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(2).foregroundStyle(apricot).opacity(fadeIn(p))
            frameImage(story.firstImage, fallback: "door.left.hand.open").opacity(fadeIn(p, delay: 0.1)).scaleEffect(1.04 - 0.04 * p)
            Text(story.firstSeconds > 0 ? DurationText.short(story.firstSeconds) : "—")
                .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(cream).opacity(fadeIn(p, delay: 0.25))
            Text("before the worry started").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.75)).opacity(fadeIn(p, delay: 0.35))
        }
    }

    private func growth(_ p: Double) -> some View {
        let e = ease(p)
        let value = story.firstSeconds + (story.bestSeconds - story.firstSeconds) * e
        let day = 1 + Int(Double(story.dayCount - 1) * e)
        return VStack(spacing: 26) {
            Text("Day \(day)").font(.system(size: 22, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(2).foregroundStyle(apricot)
            Text(DurationText.clock(value)).font(.system(size: 80, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(cream)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(LinearGradient(colors: [apricot, Color(hex: 0xF0BC5E)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(18, proxy.size.width * CGFloat(story.bestSeconds > 0 ? value / story.bestSeconds : 0)))
                }
            }
            .frame(height: 18)
            Text("small calm steps, every day").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.75))
        }
    }

    private func outro(_ p: Double) -> some View {
        VStack(spacing: 22) {
            Text("Day \(story.dayCount)").font(.system(size: 22, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(2).foregroundStyle(apricot)
            frameImage(story.latestImage ?? story.photo, fallback: "house.fill").opacity(fadeIn(p))
            Text("\(DurationText.short(story.bestSeconds)) alone, calm").font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(cream).multilineTextAlignment(.center)
            if let improvement = story.improvementText {
                Text(improvement).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0x24443B))
                    .padding(.horizontal, 16).padding(.vertical, 8).background(apricot, in: Capsule())
                    .opacity(fadeIn(p, delay: 0.2))
            }
            Spacer().frame(height: 10)
            HStack(spacing: 10) {
                StayMark(faceColor: Color(hex: 0x24443B)).frame(width: 34, height: 34)
                Text("Made with Stay").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(cream)
            }
            .opacity(fadeIn(p, delay: 0.4))
        }
    }

    private func photo(size: CGFloat) -> some View {
        Group {
            if let photo = story.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                ZStack {
                    StayPalette.sunriseGradient
                    Image(systemName: "pawprint.fill").font(.system(size: size * 0.4)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(cream, lineWidth: 5))
    }

    private func frameImage(_ image: UIImage?, fallback: String) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.1)
                Image(systemName: fallback).font(.system(size: 60)).foregroundStyle(cream.opacity(0.7))
            }
        }
        .frame(width: 290, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
