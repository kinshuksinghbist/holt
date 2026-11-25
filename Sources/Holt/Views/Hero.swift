import HoltCore
import SwiftUI

/// Timer hero shared by the menu bar panel and the main window: mode, climb scene,
/// jelly timer and the state's controls.
struct TimerHero: View {
    let model: AppModel
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 10 : 16) {
            ModeChip(title: model.modeTitle, mode: model.animationMode)
            ClimbView(progress: model.progress, mode: model.animationMode)
                .frame(height: compact ? 56 : 120)
            JellyTimer(model: model, restRadius: compact ? 50 : 76)
            ActionButtons(model: model, compact: compact)
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity)
        .holtGlass(cornerRadius: 20)
        .animation(.snappy, value: model.animationMode)
    }
}

struct ModeChip: View {
    let title: String
    let mode: AnimationMode

    var body: some View {
        Label(title, systemImage: mode.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(mode.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(mode.tint)
            .contentTransition(.opacity)
    }
}

/// The controls for the current state, from `SessionState.availableActions`.
struct ActionButtons: View {
    let model: AppModel
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.state.availableActions, id: \.self) { action in
                button(for: action)
            }
        }
        .controlSize(compact ? .regular : .large)
    }

    @ViewBuilder
    private func button(for action: SessionAction) -> some View {
        let title = Voice.label(for: action, tone: model.toneBand)
        switch action {
        case .startWork, .startNext, .resume:
            Button(title) { start(action) }
                .buttonStyle(.borderedProminent)
                .tint(model.animationMode == .paused ? AnimationMode.work.tint : model.animationMode.tint)
                .keyboardShortcut(.defaultAction)
        case .endSession:
            Button(title, role: .destructive) { model.perform(action) }
                .buttonStyle(.bordered)
        default:
            Button(title) { model.perform(action) }
                .buttonStyle(.bordered)
        }
    }

    private func start(_ action: SessionAction) {
        if action == .resume {
            model.perform(.resume)
        } else {
            model.startUpcoming()
        }
    }
}

struct ToneSlider: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Holt's tone").font(.caption.weight(.medium))
                Spacer()
                Text(model.toneBand.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Slider(value: $model.tone, in: 0...1)
                .onChange(of: model.tone) { model.saveTone() }
            HStack {
                Text("Polite")
                Spacer()
                Text("Punchy")
                Spacer()
                Text("Strict")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Holt's tone, \(model.toneBand.title)")
    }
}

/// Holt's latest line.
struct HoltQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(10)
        .holtGlass(cornerRadius: 12)
        .animation(.easeInOut(duration: 0.25), value: text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Holt says: \(text)")
    }
}

/// Placeholder for the Rive mascot: a climber moves up the mountain as the session
/// progresses and plants a flag at the top; the sun comes out on breaks.
struct ClimbView: View {
    let progress: Double
    let mode: AnimationMode

    var body: some View {
        // Copy inputs into locals so the renderer closure never touches the (main-actor) view.
        let progress = progress
        let mode = mode
        let tint = mode.tint
        return Canvas { context, size in
            let w = size.width
            let h = size.height
            let foot = CGPoint(x: 0, y: h)
            let peak = CGPoint(x: w * 0.6, y: h * 0.1)

            var mountain = Path()
            mountain.move(to: foot)
            mountain.addLine(to: peak)
            mountain.addLine(to: CGPoint(x: w, y: h))
            mountain.closeSubpath()
            context.fill(mountain, with: .color(Color.secondary.opacity(0.22)))

            if mode == .rest {
                let d = h * 0.34
                context.fill(Path(ellipseIn: CGRect(x: w * 0.8, y: h * 0.05, width: d, height: d)),
                             with: .color(Color.orange.opacity(0.85)))
            }

            let climbing = mode == .work || mode == .paused
            let p = climbing ? min(1, max(0, progress)) : 0
            let base = lerp(foot, peak, 0.1)
            let climber = lerp(foot, peak, 0.1 + 0.9 * p)

            var trail = Path()
            trail.move(to: base)
            trail.addLine(to: climber)
            context.stroke(trail, with: .color(tint),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))

            let r: CGFloat = 6
            context.fill(Path(ellipseIn: CGRect(x: climber.x - r, y: climber.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(tint))

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
        .accessibilityLabel("Climb progress \(Int(progress * 100)) percent")
    }
}

/// Point a fraction `t` of the way from `a` to `b`.
private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
