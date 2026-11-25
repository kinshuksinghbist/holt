import RiveRuntime
import SwiftUI

/// Mascot animation layer driven by `progress` (0 → 1) and `mode` (work, rest, paused, idle).
/// Uses the Rive runtime when `holt_mascot.riv` is bundled, falling back to `ClimbView`.
struct MascotAnimationView: View {
    let progress: Double
    let mode: AnimationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion, HoltResources.bundle.url(forResource: "holt_mascot", withExtension: "riv") != nil {
            RiveMascotLayer(progress: progress, mode: mode)
                .accessibilityLabel(accessibilityDescription)
        } else {
            ClimbView(progress: progress, mode: mode, reduceMotion: reduceMotion)
                .accessibilityLabel(accessibilityDescription)
        }
    }

    private var accessibilityDescription: String {
        switch mode {
        case .idle: "Mascot at base camp, idle"
        case .work: "Mascot climbing mountain, \(Int(progress * 100)) percent complete"
        case .paused: "Mascot paused mid-climb at \(Int(progress * 100)) percent"
        case .rest: "Mascot relaxing during break"
        }
    }
}

private struct RiveMascotLayer: View {
    let progress: Double
    let mode: AnimationMode
    @StateObject private var riveModel = RiveViewModel(
        fileName: "holt_mascot",
        extension: ".riv",
        in: HoltResources.bundle,
        stateMachineName: "HoltStateMachine"
    )

    var body: some View {
        riveModel.view()
            .onAppear { syncInputs() }
            .onChange(of: progress) { _, _ in syncInputs() }
            .onChange(of: mode) { _, _ in syncInputs() }
    }

    private func syncInputs() {
        riveModel.setInput("progress", value: progress * 100.0)
        let modeCode: Double
        switch mode {
        case .idle: modeCode = 0
        case .work: modeCode = 1
        case .rest: modeCode = 2
        case .paused: modeCode = 3
        }
        riveModel.setInput("mode", value: modeCode)
    }
}

/// Built-in SwiftUI mascot illustration: climbs the mountain during work, plants a flag at 1.0,
/// chills in the sun on breaks, and taps a foot while paused.
struct ClimbView: View {
    let progress: Double
    let mode: AnimationMode
    let reduceMotion: Bool

    var body: some View {
        let progress = progress
        let mode = mode
        let tint = mode.tint
        let reduceMotion = reduceMotion

        return TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || (mode != .rest && mode != .paused))) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawMascotScene(context: &context, size: size, progress: progress, mode: mode, tint: tint, phase: reduceMotion ? 0 : phase)
            }
        }
    }
}

private func drawMascotScene(
    context: inout GraphicsContext,
    size: CGSize,
    progress: Double,
    mode: AnimationMode,
    tint: Color,
    phase: Double
) {
    let w = size.width
    let h = size.height
    let foot = CGPoint(x: w * 0.06, y: h * 0.94)
    let peak = CGPoint(x: w * 0.56, y: h * 0.14)
    let rightBase = CGPoint(x: w * 0.96, y: h * 0.94)

    // Mountain body
    var mountain = Path()
    mountain.move(to: foot)
    mountain.addLine(to: peak)
    mountain.addLine(to: rightBase)
    mountain.closeSubpath()
    context.fill(mountain, with: .color(Color.secondary.opacity(0.20)))

    // Snow cap
    let capLeft = lerp(peak, foot, 0.25)
    let capRight = lerp(peak, rightBase, 0.25)
    var snow = Path()
    snow.move(to: peak)
    snow.addLine(to: capLeft)
    snow.addLine(to: CGPoint(x: peak.x, y: capLeft.y + 4))
    snow.addLine(to: capRight)
    snow.closeSubpath()
    context.fill(snow, with: .color(Color.white.opacity(0.42)))

    // Break sun + mascot chilling
    if mode == .rest {
        let sunR = h * 0.28
        let pulse = 1.0 + 0.06 * sin(phase * 2.0)
        let sunRect = CGRect(x: w * 0.78 - sunR * pulse / 2, y: h * 0.22 - sunR * pulse / 2, width: sunR * pulse, height: sunR * pulse)
        context.fill(Path(ellipseIn: sunRect), with: .color(Color.orange.opacity(0.85)))

        let chillPos = CGPoint(x: w * 0.78, y: h * 0.80 + 2.0 * sin(phase * 3.0))
        context.fill(Path(ellipseIn: CGRect(x: chillPos.x - 7, y: chillPos.y - 7, width: 14, height: 14)), with: .color(tint))
        return
    }

    // Climb trail & mascot dot
    let climbing = mode == .work || mode == .paused
    let p = climbing ? min(1, max(0, progress)) : 0
    let base = lerp(foot, peak, 0.08)
    let climber = lerp(foot, peak, 0.08 + 0.92 * p)

    var trail = Path()
    trail.move(to: base)
    trail.addLine(to: climber)
    context.stroke(trail, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))

    let bobY = mode == .paused ? abs(sin(phase * 5.0)) * 2.5 : 0
    let r: CGFloat = 6.5
    context.fill(
        Path(ellipseIn: CGRect(x: climber.x - r, y: climber.y - r - bobY, width: 2 * r, height: 2 * r)),
        with: .color(tint)
    )

    // Flag at peak on completion
    if p >= 0.999 {
        var pole = Path()
        pole.move(to: peak)
        pole.addLine(to: CGPoint(x: peak.x, y: peak.y - 18))
        context.stroke(pole, with: .color(Color.primary), lineWidth: 2)
        var flag = Path()
        flag.move(to: CGPoint(x: peak.x, y: peak.y - 18))
        flag.addLine(to: CGPoint(x: peak.x + 14, y: peak.y - 14))
        flag.addLine(to: CGPoint(x: peak.x, y: peak.y - 10))
        flag.closeSubpath()
        context.fill(flag, with: .color(Color.red))
    }
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
