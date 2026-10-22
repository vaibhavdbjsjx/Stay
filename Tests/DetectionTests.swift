import CoreGraphics
import XCTest
@testable import Stay

final class DetectionTests: XCTestCase {
    private let balanced = DetectionParameters.forSensitivity(.balanced)

    func testSingleBarkIsIgnored() {
        var aggregator = DistressAggregator(parameters: balanced)
        XCTAssertNil(aggregator.observe(scores: ["dog_bark": 0.95], at: 0))
        for t in stride(from: 0.75, through: 20, by: 0.75) {
            XCTAssertNil(aggregator.observe(scores: ["speech": 0.8], at: t))
        }
    }

    func testSustainedBarkingBecomesOneEvent() {
        var aggregator = DistressAggregator(parameters: balanced)
        var events: [DetectedSign] = []
        for t in stride(from: 10.0, through: 25.0, by: 0.75) {
            if let e = aggregator.observe(scores: ["dog_bark": 0.85, "dog": 0.9], at: t) { events.append(e) }
        }
        XCTAssertEqual(events.count, 1, "Cooldown should merge one barking bout into one event")
        XCTAssertEqual(events.first?.kind, .bark)
        XCTAssertEqual(events.first?.offset, 10)
        XCTAssertEqual(events.first?.confidence ?? 0, 0.85, accuracy: 0.001)
    }

    func testCooldownAllowsLaterSecondEvent() {
        var aggregator = DistressAggregator(parameters: balanced)
        var events: [DetectedSign] = []
        for t in stride(from: 0.0, through: 80.0, by: 0.75) {
            if let e = aggregator.observe(scores: ["dog_howl": 0.8], at: t) { events.append(e) }
        }
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.kind == .howl })
    }

    func testWhimperUsesLowerThreshold() {
        var aggregator = DistressAggregator(parameters: balanced)
        var event: DetectedSign?
        for t in stride(from: 0.0, through: 5.0, by: 0.75) {
            event = event ?? aggregator.observe(scores: ["dog_whimper": 0.5], at: t)
        }
        XCTAssertEqual(event?.kind, .whimper)
    }

    func testDominantKindWins() {
        var aggregator = DistressAggregator(parameters: balanced)
        _ = aggregator.observe(scores: ["dog_bark": 0.7], at: 0)
        _ = aggregator.observe(scores: ["dog_howl": 0.9], at: 1)
        let event = aggregator.observe(scores: ["dog_howl": 0.9], at: 2)
        XCTAssertEqual(event?.kind, .howl)
    }

    func testSensitivityChangesHowQuicklyWeAlert() {
        func firstEventTime(_ sensitivity: DetectionSensitivity, confidence: Double) -> TimeInterval? {
            var aggregator = DistressAggregator(parameters: .forSensitivity(sensitivity))
            for t in stride(from: 0.0, through: 30, by: 0.75) {
                if aggregator.observe(scores: ["dog_bark": confidence], at: t) != nil { return t }
            }
            return nil
        }
        XCTAssertNil(firstEventTime(.relaxed, confidence: 0.65), "Relaxed ignores moderate barks")
        XCTAssertNotNil(firstEventTime(.balanced, confidence: 0.65))
        XCTAssertLessThan(firstEventTime(.watchful, confidence: 0.65)!, firstEventTime(.balanced, confidence: 0.65)!)
    }

    func testStrongGenericDogSoundCounts() {
        var aggregator = DistressAggregator(parameters: balanced)
        var event: DetectedSign?
        for t in stride(from: 0.0, through: 5, by: 0.75) {
            event = event ?? aggregator.observe(scores: ["dog": 0.9], at: t)
        }
        XCTAssertEqual(event?.kind, .bark)
    }

    // MARK: Pacing

    func testPacingBackAndForthIsDetected() {
        var analyzer = PacingAnalyzer(parameters: balanced, sampleInterval: 0.5)
        var event: DetectedSign?
        // Walk left↔right across the frame every 2.5 s.
        for i in 0..<60 {
            let t = Double(i) * 0.5
            let phase = (t.truncatingRemainder(dividingBy: 5)) / 5
            let x = phase < 0.5 ? 0.2 + phase * 1.2 : 0.8 - (phase - 0.5) * 1.2
            event = event ?? analyzer.observe(position: CGPoint(x: x, y: 0.5), at: t)
        }
        XCTAssertEqual(event?.kind, .pacing)
    }

    func testRestingDogIsNotPacing() {
        var analyzer = PacingAnalyzer(parameters: balanced, sampleInterval: 0.5)
        for i in 0..<120 {
            let jitter = Double(i % 3) * 0.005
            XCTAssertNil(analyzer.observe(position: CGPoint(x: 0.5 + jitter, y: 0.6), at: Double(i) * 0.5))
        }
    }

    func testNoDetectionWithoutEnoughSightings() {
        var analyzer = PacingAnalyzer(parameters: balanced, sampleInterval: 0.5)
        for i in 0..<60 {
            let point: CGPoint? = i % 4 == 0 ? CGPoint(x: i % 8 == 0 ? 0.1 : 0.9, y: 0.5) : nil
            XCTAssertNil(analyzer.observe(position: point, at: Double(i) * 0.5))
        }
    }

    // MARK: Level timeline

    func testLevelTimelineKeepsPeakPerBucket() {
        var timeline = LevelTimeline(interval: 5)
        timeline.add(level: 0.1, at: 0)
        timeline.add(level: 0.6, at: 2)
        timeline.add(level: 0.2, at: 6)
        timeline.add(level: 1.4, at: 16)
        XCTAssertEqual(timeline.finalized(), [0.6, 0.2, 0, 1.0])
    }
}
