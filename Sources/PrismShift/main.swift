import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: MainWindowController?
    private let dragMonitor = DragMonitor()
    private var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installKeyboardMenus()
        let controller = MainWindowController()
        windowController = controller
        dragMonitor.onStart = { [weak controller] urls, cursor, mode in
            controller?.showFiles(urls, at: cursor, mode: mode)
        }
        dragMonitor.onUpdate = { [weak controller] flags in controller?.updateDrag(flags: flags) }
        dragMonitor.onEnd = { [weak controller] in controller?.dragEnded() }
        dragMonitor.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "PrismShift")
        item.button?.toolTip = "Drag a file, tap Shift, drop on a format"
        let menu = NSMenu()
        let hint = NSMenuItem(title: "Drag a file + ⇧ to convert", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Choose Files…", action: #selector(chooseFiles), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Show Drop Target", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Dismiss Wheel", action: #selector(dismissWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PrismShift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        if pendingFiles.isEmpty { controller.showLauncher() }
        else { controller.showSelection(pendingFiles); pendingFiles = [] }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if let windowController { windowController.showSelection(files) }
        else { pendingFiles = files }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { dragMonitor.stop() }

    private func installKeyboardMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PrismShift")
        appMenu.addItem(NSMenuItem(title: "Quit PrismShift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func showWindow() { windowController?.showLauncher() }
    @objc private func chooseFiles() { windowController?.chooseFiles() }
    @objc private func dismissWindow() { windowController?.dismiss() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
