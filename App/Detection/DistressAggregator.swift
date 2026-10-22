import CoreGraphics
import Foundation

/// Tuning for each sensitivity level. Centralised so the camera, tests and
/// settings screen all agree.
struct DetectionParameters: Equatable, Sendable {
    var minConfidence: Double
    /// Lower bar for whining, which is quiet and scores lower.
    var whimperConfidence: Double
    var hitsRequired: Int
    var persistenceWindow: TimeInterval
    var cooldown: TimeInterval
    var pacingWindow: TimeInterval
    var pacingPathLength: Double
    var pacingReversals: Int
    var pacingCooldown: TimeInterval

    static func forSensitivity(_ sensitivity: DetectionSensitivity) -> DetectionParameters {
        switch sensitivity {
        case .relaxed:
            DetectionParameters(minConfidence: 0.75, whimperConfidence: 0.6, hitsRequired: 4, persistenceWindow: 10, cooldown: 45,
                                pacingWindow: 20, pacingPathLength: 2.6, pacingReversals: 4, pacingCooldown: 90)
        case .balanced:
            DetectionParameters(minConfidence: 0.6, whimperConfidence: 0.45, hitsRequired: 3, persistenceWindow: 8, cooldown: 30,
                                pacingWindow: 20, pacingPathLength: 1.9, pacingReversals: 3, pacingCooldown: 60)
        case .watchful:
            DetectionParameters(minConfidence: 0.45, whimperConfidence: 0.35, hitsRequired: 2, persistenceWindow: 6, cooldown: 20,
                                pacingWindow: 20, pacingPathLength: 1.3, pacingReversals: 2, pacingCooldown: 45)
        }
    }
}

/// A detected sign of distress before the owner has reviewed it.
struct DetectedSign: Equatable, Sendable {
    var offset: TimeInterval
    var kind: DistressKind
    var confidence: Double
    var duration: TimeInterval
}

/// Turns a stream of SoundAnalysis classifications into distress events.
/// A single woof is ignored; sustained vocalisation becomes one event.
struct DistressAggregator: Sendable {
    /// Built-in classifier labels (SNClassifierIdentifier.version1) we listen for.
    static let labelKinds: [String: DistressKind] = [
        "dog_bark": .bark,
        "dog_bow_wow": .bark,
        "dog_howl": .howl,
        "dog_whimper": .whimper,
        "dog_growl": .growl,
    ]
    static let genericDogLabel = "dog"
    static let allLabels = Array(labelKinds.keys) + [genericDogLabel]

    private struct Hit: Sendable {
        var time: TimeInterval
        var kind: DistressKind
        var confidence: Double
    }

    var parameters: DetectionParameters
    private var hits: [Hit] = []
    private var lastEventTime: TimeInterval?

    init(parameters: DetectionParameters) {
        self.parameters = parameters
    }

    /// Feed one classification window. Returns an event when distress is confirmed.
    mutating func observe(scores: [String: Double], at time: TimeInterval) -> DetectedSign? {
        if let hit = strongestHit(scores: scores, at: time) {
            hits.append(hit)
        }
        hits.removeAll { time - $0.time > parameters.persistenceWindow }

        guard hits.count >= parameters.hitsRequired else { return nil }
        if let last = lastEventTime, time - last < parameters.cooldown { return nil }

        lastEventTime = time
        let first = hits.map(\.time).min() ?? time
        var weights: [DistressKind: Double] = [:]
        for hit in hits { weights[hit.kind, default: 0] += hit.confidence }
        let kind = weights.max { $0.value < $1.value }?.key ?? .bark
        let confidence = hits.map(\.confidence).reduce(0, +) / Double(hits.count)
        let event = DetectedSign(offset: first, kind: kind, confidence: confidence, duration: max(1, time - first))
        hits.removeAll()
        return event
    }

    private func strongestHit(scores: [String: Double], at time: TimeInterval) -> Hit? {
        var best: Hit?
        for (label, kind) in Self.labelKinds {
            guard let confidence = scores[label] else { continue }
            let threshold = kind == .whimper ? parameters.whimperConfidence : parameters.minConfidence
            guard confidence >= threshold else { continue }
            if confidence > (best?.confidence ?? 0) {
                best = Hit(time: time, kind: kind, confidence: confidence)
            }
        }
        // A strong generic "dog" sound with no specific label still counts as vocalising.
        if best == nil, let generic = scores[Self.genericDogLabel], generic >= max(parameters.minConfidence, 0.7) {
            best = Hit(time: time, kind: .bark, confidence: generic)
        }
        return best
    }
}

/// Detects pacing from the dog's position over time (normalised 0…1 frame coordinates).
struct PacingAnalyzer: Sendable {
    private struct Sample: Sendable {
        var time: TimeInterval
        var point: CGPoint
    }

    var parameters: DetectionParameters
    /// Expected seconds between position samples, used for coverage.
    var sampleInterval: TimeInterval = 0.5
    private var samples: [Sample] = []
    private var lastEventTime: TimeInterval?

    init(parameters: DetectionParameters, sampleInterval: TimeInterval = 0.5) {
        self.parameters = parameters
        self.sampleInterval = sampleInterval
    }

    mutating func observe(position: CGPoint?, at time: TimeInterval) -> DetectedSign? {
        if let position {
            samples.append(Sample(time: time, point: position))
        }
        samples.removeAll { time - $0.time > parameters.pacingWindow }

        let expected = parameters.pacingWindow / sampleInterval
        guard Double(samples.count) >= expected * 0.6 else { return nil }
        if let last = lastEventTime, time - last < parameters.pacingCooldown { return nil }

        var path = 0.0
        var reversals = 0
        var lastDirection = 0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let dx = Double(b.point.x - a.point.x)
            let dy = Double(b.point.y - a.point.y)
            path += (dx * dx + dy * dy).squareRoot()
            // Reversals on the dominant axis of travel; ignore jitter.
            let delta = abs(dx) >= abs(dy) ? dx : dy
            guard abs(delta) > 0.03 else { continue }
            let direction = delta > 0 ? 1 : -1
            if lastDirection != 0 && direction != lastDirection { reversals += 1 }
            lastDirection = direction
        }

        guard path >= parameters.pacingPathLength, reversals >= parameters.pacingReversals else { return nil }
        lastEventTime = time
        let first = samples.first?.time ?? time
        let confidence = min(1, 0.5 + 0.5 * (path / parameters.pacingPathLength - 1))
        samples.removeAll()
        return DetectedSign(offset: first, kind: .pacing, confidence: max(0.5, confidence), duration: time - first)
    }
}

/// Collapses per-second sound levels into a compact timeline for charts.
struct LevelTimeline: Sendable {
    let interval: TimeInterval
    private(set) var buckets: [Float] = []
    private var currentPeak: Float = 0
    private var currentBucketStart: TimeInterval = 0

    init(interval: TimeInterval = 5) {
        self.interval = interval
    }

    mutating func add(level: Float, at time: TimeInterval) {
        while time - currentBucketStart >= interval {
            buckets.append(currentPeak)
            currentPeak = 0
            currentBucketStart += interval
        }
        currentPeak = max(currentPeak, min(1, max(0, level)))
    }

    func finalized() -> [Float] {
        buckets + [currentPeak]
    }
}
