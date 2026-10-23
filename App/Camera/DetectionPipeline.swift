@preconcurrency import AVFoundation
import CoreImage
import Foundation
import SoundAnalysis
import UIKit
import Vision

/// Everything the camera device does with sensor data. Runs on private queues
/// and reports back through `@Sendable` callbacks; all analysis is on device.
final class DetectionPipeline: NSObject, @unchecked Sendable {
    struct Callbacks: Sendable {
        var onLevel: @Sendable (Float) -> Void = { _ in }
        var onSign: @Sendable (DetectedSign, Data?, [Float]) -> Void = { _, _, _ in }
        /// Small JPEG frames for the nearby live view (about 4 per second).
        var onLiveFrame: @Sendable (Data) -> Void = { _ in }
        /// A larger JPEG every few seconds for the cloud near-live view.
        var onSnapshot: @Sendable (Data) -> Void = { _ in }
    }

    enum SetupIssue: Sendable {
        case noCamera
        case noMicrophone
        case soundAnalysisUnavailable
    }

    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "stay.capture.session")
    private let videoQueue = DispatchQueue(label: "stay.capture.video")
    private let analysisQueue = DispatchQueue(label: "stay.analysis")
    private let audioEngine = AVAudioEngine()
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var callbacks = Callbacks()

    // State below is only touched on `analysisQueue`.
    private var aggregator = DistressAggregator(parameters: .forSensitivity(.balanced))
    private var pacing = PacingAnalyzer(parameters: .forSensitivity(.balanced))
    private var timeline = LevelTimeline(interval: 5)
    private var recentLevels: [Float] = []
    private var lastSecondPeak: Float = 0
    private var lastSecondMark: TimeInterval = 0
    private var sessionStart: Date?

    // State below is only touched on `videoQueue`.
    private var lastLiveFrame: TimeInterval = 0
    private var lastSnapshot: TimeInterval = 0
    private var lastVision: TimeInterval = 0
    private var latestJPEG: Data?
    private var liveFramesEnabled = false
    private var rotationAngle: CGFloat = 90

    private(set) var issues: [SetupIssue] = []

    func configure(callbacks: Callbacks, sensitivity: DetectionSensitivity) {
        self.callbacks = callbacks
        analysisQueue.sync {
            aggregator = DistressAggregator(parameters: .forSensitivity(sensitivity))
            pacing = PacingAnalyzer(parameters: .forSensitivity(sensitivity))
        }
    }

    func setSensitivity(_ sensitivity: DetectionSensitivity) {
        analysisQueue.async {
            self.aggregator = DistressAggregator(parameters: .forSensitivity(sensitivity))
            self.pacing = PacingAnalyzer(parameters: .forSensitivity(sensitivity))
        }
    }

    func setLiveFramesEnabled(_ enabled: Bool) {
        videoQueue.async { self.liveFramesEnabled = enabled }
    }

    func setRotation(_ angle: CGFloat) {
        videoQueue.async { self.rotationAngle = angle }
        sessionQueue.async {
            for output in self.captureSession.outputs {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    // MARK: Lifecycle

    /// Starts camera, microphone and analysers. Returns problems it couldn't work around.
    func start() async -> [SetupIssue] {
        var found: [SetupIssue] = []
        if !(await startVideo()) { found.append(.noCamera) }
        switch startAudio() {
        case .ok: break
        case .noMicrophone: found.append(.noMicrophone)
        case .noClassifier: found.append(.soundAnalysisUnavailable)
        }
        issues = found
        return found
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        sessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Begins attributing events and levels to a session.
    func beginSession(at start: Date) {
        analysisQueue.async {
            self.sessionStart = start
            self.timeline = LevelTimeline(interval: 5)
            self.aggregator = DistressAggregator(parameters: self.aggregator.parameters)
            self.pacing = PacingAnalyzer(parameters: self.pacing.parameters)
        }
    }

    /// Stops attributing and returns the session's sound-level timeline.
    func endSession() -> [Float] {
        analysisQueue.sync {
            let levels = sessionStart == nil ? [] : timeline.finalized()
            sessionStart = nil
            return levels
        }
    }

    // MARK: Video

    private func startVideo() async -> Bool {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return false }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                let session = self.captureSession
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                for input in session.inputs { session.removeInput(input) }
                for output in session.outputs { session.removeOutput(output) }
                guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                if session.canAddOutput(output) { session.addOutput(output) }
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                // Low frame rate keeps the device cool on long sessions.
                if (try? device.lockForConfiguration()) != nil {
                    let range = device.activeFormat.videoSupportedFrameRateRanges.first
                    if let range, range.minFrameRate <= 15 {
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    }
                    device.unlockForConfiguration()
                }
                session.commitConfiguration()
                session.startRunning()
                continuation.resume(returning: true)
            }
        }
    }

    // MARK: Audio

    private enum AudioResult { case ok, noMicrophone, noClassifier }

    private func startAudio() -> AudioResult {
        // Never touch the audio engine without permission: it can stall when access is denied.
        guard AVAudioApplication.shared.recordPermission == .granted else { return .noMicrophone }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
        } catch {
            return .noMicrophone
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return .noMicrophone }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        var classifierReady = false
        if let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            classifierReady = (try? analyzer.add(request, withObserver: self)) != nil
        }
        streamAnalyzer = analyzer

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
            guard let self else { return }
            let level = Self.normalizedLevel(buffer)
            let position = time.sampleTime
            self.analysisQueue.async {
                self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: position)
                self.record(level: level)
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            return .noMicrophone
        }
        return classifierReady ? .ok : .noClassifier
    }

    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        // Map -60 dB … -5 dB onto 0 … 1.
        return min(1, max(0, (decibels + 60) / 55))
    }

    /// analysisQueue
    private func record(level: Float) {
        callbacks.onLevel(level)
        let now = Date.now.timeIntervalSinceReferenceDate
        lastSecondPeak = max(lastSecondPeak, level)
        if now - lastSecondMark >= 1 {
            recentLevels.append(lastSecondPeak)
            if recentLevels.count > 30 { recentLevels.removeFirst(recentLevels.count - 30) }
            lastSecondPeak = 0
            lastSecondMark = now
        }
        if let start = sessionStart {
            timeline.add(level: level, at: Date.now.timeIntervalSince(start))
        }
    }

    /// analysisQueue
    private func handle(scores: [String: Double]) {
        guard let start = sessionStart else { return }
        let offset = Date.now.timeIntervalSince(start)
        if let sign = aggregator.observe(scores: scores, at: offset) {
            emit(sign)
        }
    }

    /// analysisQueue
    private func handle(position: CGPoint?) {
        guard let start = sessionStart else { return }
        if let sign = pacing.observe(position: position, at: Date.now.timeIntervalSince(start)) {
            emit(sign)
        }
    }

    /// analysisQueue
    private func emit(_ sign: DetectedSign) {
        let levels = recentLevels
        let snapshot = videoQueue.sync { latestJPEG }
        callbacks.onSign(sign, snapshot, levels)
    }

    // MARK: Frames

    fileprivate func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Date.now.timeIntervalSinceReferenceDate

        if now - lastVision >= 0.5 {
            lastVision = now
            let position = Self.dogPosition(in: pixelBuffer)
            analysisQueue.async { self.handle(position: position) }
        }

        let wantsLive = liveFramesEnabled && now - lastLiveFrame >= 0.25
        let wantsSnapshot = now - lastSnapshot >= 4
        guard wantsLive || wantsSnapshot else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        if wantsLive {
            lastLiveFrame = now
            if let data = uiImage.resized(maxSide: 360).jpegData(compressionQuality: 0.5) {
                callbacks.onLiveFrame(data)
            }
        }
        if wantsSnapshot {
            lastSnapshot = now
            if let data = uiImage.resized(maxSide: 720).jpegData(compressionQuality: 0.6) {
                latestJPEG = data
                callbacks.onSnapshot(data)
            }
        }
    }

    /// Centre of the dog in normalised coordinates, from animal body pose or,
    /// failing that, the animal bounding box.
    private static func dogPosition(in pixelBuffer: CVPixelBuffer) -> CGPoint? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let pose = VNDetectAnimalBodyPoseRequest()
        if (try? handler.perform([pose])) != nil,
           let observation = pose.results?.first,
           let points = try? observation.recognizedPoints(.all) {
            let confident = points.values.filter { $0.confidence > 0.3 }
            if confident.count >= 3 {
                let x = confident.map(\.location.x).reduce(0, +) / CGFloat(confident.count)
                let y = confident.map(\.location.y).reduce(0, +) / CGFloat(confident.count)
                return CGPoint(x: x, y: y)
            }
        }
        let animals = VNRecognizeAnimalsRequest()
        if (try? handler.perform([animals])) != nil,
           let dog = animals.results?.first(where: { $0.labels.contains { $0.identifier == VNAnimalIdentifier.dog.rawValue } }) {
            return CGPoint(x: dog.boundingBox.midX, y: dog.boundingBox.midY)
        }
        return nil
    }
}

extension DetectionPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        process(sampleBuffer)
    }
}

extension DetectionPipeline: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var scores: [String: Double] = [:]
        for label in DistressAggregator.allLabels {
            if let classification = result.classification(forIdentifier: label) {
                scores[label] = classification.confidence
            }
        }
        let captured = scores
        analysisQueue.async { self.handle(scores: captured) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
