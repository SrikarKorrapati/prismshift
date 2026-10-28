import AppKit
import ImageIO
import PDFKit
import SwiftUI

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MainWindowController: NSWindowController {
    let state = WheelState()
    private var destination: WheelDropView!
    private var keyMonitor: Any?
    private var openPanel: NSOpenPanel?
    private var dropReceived = false
    private var dragGeneration = 0

    init() {
        let panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 410),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.title = "PrismShift"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)

        destination = WheelDropView(state: state)
        panel.contentView = destination
        state.onAction = { [weak self] action in self?.run(action) }
        state.onChoose = { [weak self] in self?.chooseFiles() }
        state.onClose = { [weak self] in self?.dismiss() }
        state.onReveal = { [weak self] in self?.revealOutputs() }
        destination.onFiles = { [weak self] urls, dropped in
            guard let self, !self.state.busy else { return }
            if self.state.urls != urls { self.loadFiles(urls) }
            self.state.dragging = !dropped
            if dropped { self.dropReceived = true }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            if event.type == .flagsChanged {
                self.changeMode(for: event.modifierFlags)
                return event
            }
            switch event.keyCode {
            case 53: self.dismiss(); return nil
            case 123, 126:
                self.advanceSelection(-1); return nil
            case 124, 125:
                self.advanceSelection(1); return nil
            case 36, 76:
                if let index = self.state.hovered, self.state.actions.indices.contains(index), !self.state.busy {
                    self.run(self.state.actions[index])
                } else if self.state.urls.isEmpty { self.chooseFiles() }
                return nil
            default: return event
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showLauncher() {
        guard !state.busy else { window?.orderFrontRegardless(); return }
        state.mode = .convert
        loadFiles([])
        state.dragging = false
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func chooseFiles() {
        guard !state.busy else { return }
        window?.orderOut(nil)
        let picker = NSOpenPanel()
        openPanel = picker
        picker.title = "Choose files to convert"
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self else { return }
            self.openPanel = nil
            if response == .OK {
                self.state.mode = .convert
                self.loadFiles(picker.urls)
                self.state.dragging = false
                self.window?.center()
                self.window?.makeKeyAndOrderFront(nil)
            } else {
                self.window?.orderFrontRegardless()
            }
        }
    }

    func showSelection(_ urls: [URL]) {
        guard !state.busy, !urls.isEmpty else { return }
        openPanel?.cancel(nil)
        state.mode = .convert
        loadFiles(urls)
        state.dragging = false
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func showFiles(_ urls: [URL], at cursor: NSPoint, mode: WheelMode = .convert) {
        guard !state.busy else { return }
        dragGeneration += 1
        dropReceived = false
        state.mode = mode
        loadFiles(urls)
        state.dragging = true
        position(at: cursor)
        window?.orderFrontRegardless()
    }

    func updateDrag(flags: NSEvent.ModifierFlags) {
        guard state.dragging, !state.busy else { return }
        changeMode(for: flags)
        if let window {
            let point = destination.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            state.hovered = WheelGeometry.actionIndex(at: point, count: state.actions.count)
        }
    }

    func dragEnded() {
        let generation = dragGeneration
        // AppKit delivers performDragOperation after the physical mouse-up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.dragGeneration == generation else { return }
            self.state.dragging = false
            if !self.dropReceived && !self.state.busy { self.dismiss() }
        }
    }

    func dismiss() {
        guard !state.busy else { return }
        window?.orderOut(nil)
        state.dragging = false
        state.hovered = nil
    }

    private func changeMode(for flags: NSEvent.ModifierFlags) {
        let mode: WheelMode?
        if flags.contains(.control) { mode = .files }
        else if flags.contains(.command) { mode = .tools }
        else if flags.contains(.shift) { mode = .convert }
        else { mode = nil }
        guard let mode, mode != state.mode, !state.busy else { return }
        state.mode = mode
        state.actions = FileAction.actions(for: state.urls, mode: mode)
        state.hovered = nil
    }

    private func advanceSelection(_ direction: Int) {
        guard !state.actions.isEmpty, !state.busy else { return }
        let current = state.hovered ?? (direction > 0 ? -1 : 0)
        state.hovered = (current + direction + state.actions.count) % state.actions.count
    }

    private func loadFiles(_ urls: [URL]) {
        state.urls = urls
        state.actions = FileAction.actions(for: urls, mode: state.mode)
        state.hovered = nil
        state.message = ""
        state.failed = false
        state.outputs = []
        guard let first = urls.first else { state.thumbnail = nil; return }
        state.thumbnail = preview(first)
        let size = urls.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        state.sizeLabel = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func preview(_ url: URL) -> NSImage {
        if FileInspector.kind(for: url) == .pdf, let page = PDFDocument(url: url)?.page(at: 0) {
            return page.thumbnail(of: NSSize(width: 100, height: 120), for: .cropBox)
        }
        if FileInspector.kind(for: url) == .image,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 120
           ] as CFDictionary) {
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func position(at cursor: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame, let window else { return }
        var origin = NSPoint(x: cursor.x - 170, y: cursor.y - 240)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - 340)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - 410)
        window.setFrameOrigin(origin)
    }

    private func revealOutputs() {
        guard !state.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(state.outputs)
    }

    private func run(_ action: FileAction) {
        guard !state.urls.isEmpty, !state.busy else { return }
        dropReceived = true
        state.dragging = false
        state.hovered = nil
        let urls = state.urls
        if action.id == .reveal {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            dismiss()
            return
        }
        if action.id == .copyPath {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            state.message = urls.count == 1 ? "Path copied" : "\(urls.count) paths copied"
            return
        }
        state.busy = true
        state.message = "Converting to \(action.title)…"
        state.failed = false
        state.outputs = []
        Task {
            let results = await ConversionService.shared.run(action: action, urls: urls)
            state.busy = false
            state.outputs = results.compactMap(\.url)
            let errors = results.filter(\.isError)
            state.failed = !errors.isEmpty
            if let error = errors.first {
                state.message = state.outputs.isEmpty ? error.message : "\(state.outputs.count) created; \(errors.count) failed. \(error.message)"
            } else {
                state.message = state.outputs.count == 1 ? "Saved \(state.outputs[0].lastPathComponent)" : "Saved \(state.outputs.count) files beside the original"
            }
        }
    }
}

@MainActor
final class WheelDropView: NSView {
    var onFiles: (([URL], Bool) -> Void)?
    private let state: WheelState
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(state: WheelState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 410))
        let host = NSHostingView(rootView: GlassWheelView(state: state))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Route the whole rounded petal through the same geometry for clicks and drops.
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard !state.busy else { return }
        state.hovered = WheelGeometry.actionIndex(at: convert(event.locationInWindow, from: nil), count: state.actions.count)
    }
    override func mouseExited(with event: NSEvent) { if !state.dragging { state.hovered = nil } }

    override func mouseDown(with event: NSEvent) {
        guard !state.busy else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - 318, point.y - 22) < 16 { state.onClose?(); return }
        if point.y > 340, !state.outputs.isEmpty { state.onReveal?(); return }
        if let index = WheelGeometry.actionIndex(at: point, count: state.actions.count) {
            state.onAction?(state.actions[index])
        } else if hypot(point.x - 170, point.y - 170) < 60 {
            state.onChoose?()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !state.busy, let urls = Self.urls(from: sender.draggingPasteboard), !urls.isEmpty else { return [] }
        onFiles?(urls, false)
        return draggingUpdated(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !state.busy else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        state.hovered = WheelGeometry.actionIndex(at: point, count: state.actions.count)
        let inHub = hypot(point.x - 170, point.y - 170) < WheelGeometry.inner
        return (state.hovered != nil || inHub) ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { state.hovered = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !state.busy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !state.busy, let urls = Self.urls(from: sender.draggingPasteboard), !urls.isEmpty else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let index = WheelGeometry.actionIndex(at: point, count: state.actions.count)
        guard index != nil || hypot(point.x - 170, point.y - 170) < WheelGeometry.inner else { return false }
        onFiles?(urls, true)
        if let index, state.actions.indices.contains(index) { state.onAction?(state.actions[index]) }
        return true
    }
    static func urls(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }
}
