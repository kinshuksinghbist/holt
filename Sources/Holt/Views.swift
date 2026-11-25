import AppKit
import HoltCore
import SwiftUI

// MARK: - Menu bar

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let title = model.menuBarTitle
        Text("\(Image(systemName: model.menuBarSymbol))\(title.isEmpty ? "" : " " + title)")
            .monospacedDigit()
    }
}

struct PanelView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Holt").font(.headline)
                Spacer()
                Button {
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Open Holt")
            }

            TimerHero(model: model, compact: true)

            ToneSlider(model: model)

            if let line = model.lastLine {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit Holt") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Main window

struct MainWindowView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TimerHero(model: model, compact: false)
                    .frame(maxWidth: .infinity)

                ToneSlider(model: model)
                    .frame(maxWidth: 360)

                Text("Coming next")
                    .font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ComingSoonCard(title: "Jelly timer", detail: "Stretch it for a longer session.", milestone: "M1")
                    ComingSoonCard(title: "Todos, lists & notes", detail: "With history and rollover.", milestone: "M2")
                    ComingSoonCard(title: "App & website tracking", detail: "Including YouTube categories.", milestone: "M3")
                    ComingSoonCard(title: "Screen understanding", detail: "On-device OCR, opt-in.", milestone: "M4")
                    ComingSoonCard(title: "Stats", detail: "Heatmap, ribbon, switch river.", milestone: "M5")
                    ComingSoonCard(title: "Holt's nudges", detail: "Reminders that know your history.", milestone: "M6")
                }
            }
            .padding(24)
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

struct ComingSoonCard: View {
    let title: String
    let detail: String
    let milestone: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(milestone).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holtGlass(cornerRadius: 14)
    }
}

// MARK: - Shared pieces

struct TimerHero: View {
    let model: AppModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(model.modeTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ClimbView(progress: model.progress, mode: model.animationMode)
                .frame(height: compact ? 110 : 180)

            Text(model.remaining.map(TimeFormat.clock) ?? "--:--")
                .font(.system(size: compact ? 44 : 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            ActionButtons(model: model)
        }
        .padding(compact ? 12 : 24)
        .holtGlass(cornerRadius: 20)
    }
}

struct ActionButtons: View {
    let model: AppModel
    private static let primary: Set<SessionAction> = [.startWork, .startNext, .resume]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.state.availableActions, id: \.self) { action in
                let title = Voice.label(for: action, tone: model.toneBand)
                if Self.primary.contains(action) {
                    Button(title) { model.perform(action) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(title) { model.perform(action) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.large)
    }
}

struct ToneSlider: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
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
        .accessibilityLabel("Holt's tone")
    }
}

/// Placeholder for the Rive mascot: a dot climbs the mountain as the session progresses.
struct ClimbView: View {
    let progress: Double
    let mode: AnimationMode

    var body: some View {
        // Copy inputs into locals so the renderer closure never touches the (main-actor) view.
        let progress = progress
        let mode = mode
        return Canvas { context, size in
            let w = size.width
            let h = size.height
            let foot = CGPoint(x: 0, y: h)
            let peak = CGPoint(x: w * 0.6, y: h * 0.12)

            var mountain = Path()
            mountain.move(to: foot)
            mountain.addLine(to: peak)
            mountain.addLine(to: CGPoint(x: w, y: h))
            mountain.closeSubpath()
            context.fill(mountain, with: .color(Color.secondary.opacity(0.25)))

            if mode == .rest {
                let d = h * 0.28
                context.fill(Path(ellipseIn: CGRect(x: w * 0.8, y: h * 0.08, width: d, height: d)),
                             with: .color(Color.orange.opacity(0.85)))
            }

            let climbing = mode == .work || mode == .paused
            let p = climbing ? min(1, max(0, progress)) : 0
            let t = 0.1 + 0.9 * p
            let base = lerp(foot, peak, 0.1)
            let climber = lerp(foot, peak, t)

            var trail = Path()
            trail.move(to: base)
            trail.addLine(to: climber)
            context.stroke(trail, with: .color(Color.accentColor),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))

            let r: CGFloat = 7
            context.fill(Path(ellipseIn: CGRect(x: climber.x - r, y: climber.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color.accentColor))

            if p >= 0.999 {
                var pole = Path()
                pole.move(to: peak)
                pole.addLine(to: CGPoint(x: peak.x, y: peak.y - 22))
                context.stroke(pole, with: .color(Color.primary), lineWidth: 2)
                var flag = Path()
                flag.move(to: CGPoint(x: peak.x, y: peak.y - 22))
                flag.addLine(to: CGPoint(x: peak.x + 16, y: peak.y - 17))
                flag.addLine(to: CGPoint(x: peak.x, y: peak.y - 12))
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

extension View {
    /// Liquid Glass on macOS 26, translucent material before that.
    @ViewBuilder
    func holtGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
