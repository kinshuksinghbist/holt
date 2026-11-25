import SwiftUI

extension AnimationMode {
    /// Accent colour per mode, shared by the chip, jelly, buttons and climb scene.
    var tint: Color {
        switch self {
        case .work: .orange
        case .rest: .teal
        case .paused: .yellow
        case .idle: .indigo
        }
    }

    var symbol: String {
        switch self {
        case .work: "flame.fill"
        case .rest: "cup.and.saucer.fill"
        case .paused: "pause.fill"
        case .idle: "scope"
        }
    }
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

/// Borderless icon button with a tooltip and an accessibility label.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
