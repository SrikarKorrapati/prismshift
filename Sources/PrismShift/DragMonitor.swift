import AppKit

/// Watches public mouse/modifier state and the drag pasteboard, without a keyboard
/// event tap or Accessibility permission. A fresh drag payload is required.
@MainActor
final class DragMonitor {
    var onStart: (([URL], NSPoint, WheelMode) -> Void)?
    var onUpdate: ((NSEvent.ModifierFlags) -> Void)?
    var onEnd: (() -> Void)?
    private var timer: Timer?
    private let pasteboard = NSPasteboard(name: .drag)
    private var gate = DragGestureGate(pasteboardCount: 0)
    private var pendingURLs: [URL] = []
    private var active = false

    func start() {
        gate = DragGestureGate(pasteboardCount: pasteboard.changeCount)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let flags = NSEvent.modifierFlags
        let point = NSEvent.mouseLocation
        let requested = !flags.intersection([.control, .command, .shift]).isEmpty
        let offer = gate.shouldOffer(pressed: pressed, point: point, pasteboardCount: pasteboard.changeCount, requested: requested)
        if !pressed {
            if active { onEnd?() }
            active = false
            pendingURLs = []
            return
        }
        if active { onUpdate?(flags); return }
        let mode: WheelMode?
        if flags.contains(.control) { mode = .files }
        else if flags.contains(.command) { mode = .tools }
        else if flags.contains(.shift) { mode = .convert }
        else { mode = nil }
        guard let mode, offer else { return }
        if pendingURLs.isEmpty {
            pendingURLs = WheelDropView.urls(from: pasteboard) ?? []
        }
        guard !pendingURLs.isEmpty else { return }
        active = true
        onStart?(pendingURLs, point, mode)
    }
}
