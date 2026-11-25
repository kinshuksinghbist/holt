import Foundation
import Testing
@testable import HoltCore

@Suite("Jelly dial")
struct JellyDialTests {
    @Test func valuesAreFiveMinuteStepsThenQuarterHours() {
        #expect(JellyDial.allValues == [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 105, 120, 135, 150, 165, 180])
    }

    @Test func stretchMapsMonotonicallyWithinBounds() {
        #expect(JellyDial.minutes(forStretch: 0) == 5)
        #expect(JellyDial.minutes(forStretch: 5.9) == 5)
        #expect(JellyDial.minutes(forStretch: 6) == 10)
        #expect(JellyDial.minutes(forStretch: 10_000) == 180)
        #expect(JellyDial.minutes(forStretch: -.infinity) == 5)
        #expect(JellyDial.minutes(forStretch: .nan) == 5)
        var previous = 0
        for tenth in 0...2_000 {
            let value = JellyDial.minutes(forStretch: Double(tenth) / 10)
            #expect(value >= previous)
            previous = value
        }
    }

    @Test func stretchForMinutesRoundTrips() {
        for value in JellyDial.allValues {
            #expect(JellyDial.minutes(forStretch: JellyDial.stretch(forMinutes: value)) == value)
        }
    }

    @Test func adjustingStepsAndClamps() {
        #expect(JellyDial.adjusted(25, bySteps: 1) == 30)
        #expect(JellyDial.adjusted(60, bySteps: 1) == 75)
        #expect(JellyDial.adjusted(75, bySteps: -1) == 60)
        #expect(JellyDial.adjusted(5, bySteps: -1) == 5)
        #expect(JellyDial.adjusted(180, bySteps: 3) == 180)
        #expect(JellyDial.adjusted(27, bySteps: 0) == 25) // snaps down to a dial value
    }

    @Test func rubberBandSaturates() {
        #expect(JellyDial.rubberBand(0, limit: 40) == 0)
        #expect(JellyDial.rubberBand(10, limit: 40) < 10)
        #expect(JellyDial.rubberBand(20, limit: 40) > JellyDial.rubberBand(10, limit: 40))
        #expect(JellyDial.rubberBand(10_000, limit: 40) <= 40)
    }
}

@Suite("Jelly physics")
struct JellyBodyTests {
    private func simulate(_ jelly: inout JellyBody, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { jelly.step(by: 1.0 / 60.0) }
    }

    @Test func restingJellyStaysRound() {
        var jelly = JellyBody(restRadius: 50)
        simulate(&jelly, seconds: 1)
        #expect(jelly.isSettled)
        #expect(jelly.radii.allSatisfy { abs($0 - 50) < 0.01 })
    }

    @Test func pullBulgesTowardPointerAndThinsTheFarSide() {
        var jelly = JellyBody(count: 32, restRadius: 50)
        jelly.pull = JellyPull(angle: 0, distance: 90)
        simulate(&jelly, seconds: 3)
        #expect(jelly.radii[0] > 75)
        #expect(jelly.radii[16] < 50)
    }

    @Test func wobbleDecaysBackToRest() {
        var jelly = JellyBody(restRadius: 50)
        jelly.wobble(strength: 200)
        #expect(!jelly.isSettled)
        simulate(&jelly, seconds: 4)
        #expect(jelly.isSettled)
    }

    @Test func shrinkingRestRadiusIsFollowed() {
        var jelly = JellyBody(restRadius: 50)
        jelly.restRadius = 36
        simulate(&jelly, seconds: 3)
        #expect(jelly.radii.allSatisfy { abs($0 - 36) < 0.3 })
    }

    @Test func hostileTimeStepsCannotBreakIt() {
        var jelly = JellyBody(restRadius: 50)
        jelly.pull = JellyPull(angle: 1, distance: 500)
        jelly.step(by: 10)
        jelly.step(by: .nan)
        jelly.step(by: -1)
        jelly.step(by: .infinity)
        #expect(jelly.radii.allSatisfy { $0.isFinite && $0 > 0 && $0 < 1_000 })
    }

    @Test func settleJumpsToTarget() {
        var jelly = JellyBody(restRadius: 50)
        jelly.pull = JellyPull(angle: .pi / 2, distance: 80)
        jelly.settle()
        #expect(jelly.isSettled)
    }

    @Test func outlineIsCentred() {
        let jelly = JellyBody(count: 8, restRadius: 10)
        let points = jelly.outline(centerX: 100, centerY: 50)
        #expect(points.count == 8)
        #expect(abs(points[0].x - 110) < 1e-9 && abs(points[0].y - 50) < 1e-9)
        #expect(abs(points[2].x - 100) < 1e-9 && abs(points[2].y - 60) < 1e-9)
    }

    @Test func angularDistanceWraps() {
        #expect(abs(JellyBody.angularDistance(0.1, 2 * .pi - 0.1) - 0.2) < 1e-9)
        #expect(abs(JellyBody.angularDistance(-.pi / 2, .pi / 2) - .pi) < 1e-9)
    }
}
