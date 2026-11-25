import HoltCore
import SwiftUI

/// The jelly: shows the countdown, and when nothing is running you grab it and stretch it to
/// pick a session length — the further you pull, the longer the session. Ticks (sound +
/// trackpad haptic) at each step; let go to start. Tap to start with the shown length.
/// While a session runs it slowly shrinks; while paused it jiggles.
struct JellyTimer: View {
    let model: AppModel
    let restRadius: CGFloat

    @State private var jelly: JellyBody
    @State private var lastFrame: Date?
    @State private var dragMinutes: Int?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, restRadius: CGFloat) {
        self.model = model
        self.restRadius = restRadius
        _jelly = State(initialValue: JellyBody(count: 32, restRadius: Double(restRadius)))
    }

    private var maxVisualStretch: CGFloat { restRadius * 0.7 }
    private var side: CGFloat { (restRadius + maxVisualStretch) * 2 + 8 }

    /// Rest size: full while idle, shrinking toward 72% as the session runs out.
    private var targetRadius: Double {
        let r = Double(restRadius)
        switch model.state.phase {
        case .running, .paused: return r * (0.72 + 0.28 * model.remainingFraction)
        case .idle, .ready: return r
        }
    }

    var body: some View {
        // Only animate while something is moving; a still jelly costs nothing.
        let animating = !reduceMotion && (dragMinutes != nil || !jelly.isSettled)
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animating)) { timeline in
            canvas
                .onChange(of: timeline.date) { _, date in advance(to: date) }
        }
        .frame(width: side, height: side)
        .overlay { label }
        // Only the jelly itself is grabbable (a drag that starts on it keeps tracking outside).
        .contentShape(Circle().inset(by: maxVisualStretch + 4))
        .gesture(drag)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(by: 1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
        .onKeyPress(.downArrow) { step(by: -1) }
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onAppear {
            jelly.restRadius = targetRadius
            jelly.settle()
        }
        .onChange(of: targetRadius) { _, radius in
            jelly.restRadius = radius
            if reduceMotion { jelly.settle() }
        }
        .task(id: model.isPausedSession) {
            // Paused: a short jiggle every few seconds, still in between (no 60 fps redraw).
            while model.isPausedSession, !reduceMotion, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                if model.isPausedSession, !Task.isCancelled {
                    jelly.wobble(strength: 22)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.canSetDuration ? "Session length" : "Time left")
        .accessibilityValue(TimeFormat.clock(model.displayedSeconds))
        .accessibilityHint(model.canSetDuration ? "Adjust to change the length, activate to start" : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.adjustPending(bySteps: 1)
            case .decrement: model.adjustPending(bySteps: -1)
            @unknown default: break
            }
        }
        .accessibilityAction { model.startUpcoming() }
    }

    // MARK: Drawing

    private var canvas: some View {
        let center = Double(side / 2)
        let outline = jelly.outline(centerX: center, centerY: center).map { CGPoint(x: $0.x, y: $0.y) }
        let tint = model.animationMode.tint
        return Canvas { context, _ in
            let path = smoothClosedPath(through: outline)
            let bounds = path.boundingRect
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.95), tint.opacity(0.55)]),
                    startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                    endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
                )
            )
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
            let gloss = CGRect(x: bounds.minX + bounds.width * 0.2, y: bounds.minY + bounds.height * 0.12,
                               width: bounds.width * 0.3, height: bounds.height * 0.16)
            context.fill(Path(ellipseIn: gloss), with: .color(.white.opacity(0.3)))
        }
    }

    private var label: some View {
        let seconds = dragMinutes.map { TimeInterval($0 * 60) } ?? model.displayedSeconds
        return VStack(spacing: 2) {
            Text(TimeFormat.clock(seconds))
                .font(.system(size: restRadius * 0.42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if model.canSetDuration {
                Text(dragMinutes == nil ? "stretch me" : "let go to start")
                    .font(.system(size: max(9, restRadius * 0.16), weight: .medium))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .allowsHitTesting(false)
    }

    // MARK: Interaction

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                focused = true
                guard model.canSetDuration else { return }
                let dx = Double(value.location.x - side / 2)
                let dy = Double(value.location.y - side / 2)
                let stretch = (dx * dx + dy * dy).squareRoot() - Double(restRadius)
                guard stretch > 0 else {
                    // Back inside the jelly: no length chosen.
                    jelly.pull = nil
                    dragMinutes = nil
                    return
                }
                let minutes = JellyDial.minutes(forStretch: stretch)
                if minutes != dragMinutes {
                    dragMinutes = minutes
                    Feedback.step(haptics: model.settings.jellyHaptics, sound: model.settings.playSounds)
                }
                jelly.pull = JellyPull(
                    angle: atan2(dy, dx),
                    distance: Double(restRadius) + JellyDial.rubberBand(stretch, limit: Double(maxVisualStretch))
                )
                if reduceMotion { jelly.settle() }
            }
            .onEnded { value in
                let chosen = dragMinutes
                let moved = hypot(value.translation.width, value.translation.height)
                jelly.pull = nil
                dragMinutes = nil
                if reduceMotion { jelly.settle() } else { jelly.wobble(strength: 70) }
                guard model.canSetDuration else { return } // a poke while running: just wobble
                if let chosen {
                    if model.settings.playSounds { Sounds.playRelease() }
                    model.start(minutes: chosen)
                } else if moved < 4 {
                    model.startUpcoming()
                }
            }
    }

    private func step(by delta: Int) -> KeyPress.Result {
        guard model.canSetDuration else { return .ignored }
        model.adjustPending(bySteps: delta)
        Feedback.step(haptics: false, sound: model.settings.playSounds)
        if !reduceMotion { jelly.wobble(strength: 25) }
        return .handled
    }

    private func advance(to date: Date) {
        let dt = lastFrame.map { date.timeIntervalSince($0) } ?? (1.0 / 60.0)
        lastFrame = date
        if reduceMotion {
            jelly.settle()
            return
        }
        jelly.step(by: dt)
    }
}

/// Closed Catmull-Rom spline through the points, as cubic Béziers.
private func smoothClosedPath(through points: [CGPoint]) -> Path {
    var path = Path()
    let n = points.count
    guard n > 2 else { return path }
    path.move(to: points[0])
    for i in 0..<n {
        let p0 = points[(i + n - 1) % n]
        let p1 = points[i]
        let p2 = points[(i + 1) % n]
        let p3 = points[(i + 2) % n]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    path.closeSubpath()
    return path
}
