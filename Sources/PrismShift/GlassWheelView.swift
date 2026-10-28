import AppKit
import SwiftUI

@MainActor
final class WheelState: ObservableObject {
    @Published var urls: [URL] = []
    @Published var actions: [FileAction] = []
    @Published var mode: WheelMode = .convert
    @Published var hovered: Int?
    @Published var dragging = false
    @Published var busy = false
    @Published var message = ""
    @Published var failed = false
    @Published var outputs: [URL] = []
    @Published var thumbnail: NSImage?
    @Published var sizeLabel = ""
    var onAction: ((FileAction) -> Void)?
    var onChoose: (() -> Void)?
    var onClose: (() -> Void)?
    var onReveal: (() -> Void)?
}

enum WheelGeometry {
    static let side: CGFloat = 340
    static let center = CGPoint(x: 170, y: 170)
    static let outer: CGFloat = 146
    static let inner: CGFloat = 53

    static func labelPoint(index: Int, count: Int) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
        let radius: CGFloat = 103
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    static func petal(index: Int, count: Int) -> CGPath {
        let path = CGMutablePath()
        guard count > 0 else { return path }
        let step = 2 * CGFloat.pi / CGFloat(count)
        let gap: CGFloat = 0.018
        let a = -CGFloat.pi / 2 + CGFloat(index) * step - step / 2 + gap
        let b = a + step - gap * 2
        let corner: CGFloat = 9
        func p(_ r: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        }
        path.move(to: p(inner + corner, a))
        path.addLine(to: p(outer - corner, a))
        path.addQuadCurve(to: p(outer, a + corner / outer), control: p(outer, a))
        path.addArc(center: center, radius: outer, startAngle: a + corner / outer, endAngle: b - corner / outer, clockwise: false)
        path.addQuadCurve(to: p(outer - corner, b), control: p(outer, b))
        path.addLine(to: p(inner + corner, b))
        path.addQuadCurve(to: p(inner, b - corner / inner), control: p(inner, b))
        path.addArc(center: center, radius: inner, startAngle: b - corner / inner, endAngle: a + corner / inner, clockwise: true)
        path.addQuadCurve(to: p(inner + corner, a), control: p(inner, a))
        path.closeSubpath()
        return path
    }

    static func actionIndex(at point: CGPoint, count: Int) -> Int? {
        (0..<count).first { petal(index: $0, count: count).contains(point) }
    }
}

struct RadialPetal: Shape {
    let index: Int
    let count: Int
    func path(in rect: CGRect) -> Path { Path(WheelGeometry.petal(index: index, count: count)) }
}

struct GlassWheelView: View {
    @ObservedObject var state: WheelState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if state.urls.isEmpty {
                    launcher
                } else {
                    petals
                    hub
                }
                Button(action: { state.onClose?() }) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .position(x: 318, y: 22)
                .help("Dismiss · Escape")
                .accessibilityLabel("Dismiss wheel")
            }
            .frame(width: 340, height: 340)

            if !state.urls.isEmpty {
                footer
            }
        }
        .frame(width: 340, height: 410, alignment: .top)
    }

    @ViewBuilder private var petals: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                petalContents
            }
        } else {
            petalContents
        }
    }

    private var petalContents: some View {
        ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
            let shape = RadialPetal(index: index, count: state.actions.count)
            let point = WheelGeometry.labelPoint(index: index, count: state.actions.count)
            let highlighted = state.hovered == index
            ZStack {
                petalMaterial(shape, highlighted: highlighted)
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(highlighted ? Color.white : Color.primary)
                    .position(point)
            }
            .frame(width: 340, height: 340)
            .contentShape(shape)
            .onTapGesture { if !state.busy { state.onAction?(action) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.title)
            .accessibilityHint(action.subtitle)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !state.busy { state.onAction?(action) } }
            .help(action.subtitle)
        }
    }

    @ViewBuilder private func petalMaterial(_ shape: RadialPetal, highlighted: Bool) -> some View {
        if #available(macOS 26.0, *) {
            shape.fill(highlighted ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08))
                .glassEffect(.regular.tint(highlighted ? .accentColor : nil), in: shape)
                .overlay(shape.strokeBorderCompat(Color.white.opacity(highlighted ? 0.55 : 0.12)))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(highlighted ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.16)))
                .overlay(shape.strokeBorderCompat(Color.white.opacity(0.3)))
        }
    }

    @ViewBuilder private var hub: some View {
        if state.busy {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Converting").font(.system(size: 10, weight: .medium))
            }.position(WheelGeometry.center)
        } else if !state.dragging {
            VStack(spacing: 3) {
                if let thumbnail = state.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 44, height: 49)
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                }
                Text(state.urls.count > 1 ? "\(state.urls.count) files" : state.sizeLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
            }
            .position(WheelGeometry.center)
            .help("Choose another file")
        }
    }

    private var launcher: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc").font(.system(size: 25, weight: .light))
            Text("Drag + ⇧").font(.system(size: 13, weight: .semibold))
            Text("or click to choose").font(.system(size: 10))
        }
        .frame(width: 116, height: 116)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        .position(WheelGeometry.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Choose files")
        .accessibilityAction { state.onChoose?() }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            let hoverText = state.hovered.flatMap { state.actions.indices.contains($0) ? state.actions[$0].subtitle : nil }
            Text(state.message.isEmpty ? (hoverText ?? FileInspector.displayName(for: state.urls)) : state.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.failed ? Color.orange : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 268)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .help(state.message)
                .accessibilityLabel(state.message.isEmpty ? FileInspector.displayName(for: state.urls) : state.message)
            if !state.busy {
                Text(state.outputs.isEmpty
                     ? (state.dragging ? "Drop on a format · ⌘ tools · ⌃ files" : "Click a format · ⌘ tools · esc close")
                     : "Click here to show the result in Finder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 340, height: 66, alignment: .top)
    }
}

private extension Shape {
    func strokeBorderCompat(_ color: Color) -> some View { stroke(color, lineWidth: 0.6) }
}
