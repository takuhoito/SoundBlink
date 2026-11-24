import AppKit
import ServiceManagement

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isResetting = false
    private var lastResult: ResetResult?
    private var iconRestore: DispatchWorkItem?

    private enum Icon {
        case idle, busy, failed

        var symbolName: String {
            switch self {
            case .idle: return "hifispeaker"
            case .busy: return "arrow.triangle.2.circlepath"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = L("Click to reset the audio output. Right-click for options.")
        }
        setIcon(.idle)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        rescheduleTimer()
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
        } else {
            runReset(trigger: .manual)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach the menu so the next left click resets instead of opening it.
        statusItem.menu = nil
    }

    /// The app's own menu bar glyph (Resources/StatusIcon.pdf); nil when running unbundled.
    private lazy var statusIcon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "StatusIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }()

    private func setIcon(_ icon: Icon) {
        iconRestore?.cancel()
        if icon == .idle, let statusIcon {
            statusItem.button?.image = statusIcon
            return
        }
        let image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func flashIcon(_ icon: Icon, seconds: TimeInterval = 3) {
        setIcon(icon)
        let restore = DispatchWorkItem { [weak self] in self?.setIcon(.idle) }
        iconRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: restore)
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(actionItem(L("Reset Now"), #selector(resetNow)))
        menu.addItem(.separator())

        let periodic = actionItem(L("Periodic Reset"), #selector(togglePeriodicReset))
        periodic.state = settings.periodicResetEnabled ? .on : .off
        menu.addItem(periodic)

        let interval = NSMenuItem(title: L("Interval"), action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        var choices = Settings.intervalPresets
        if !choices.contains(settings.intervalMinutes) {
            choices.append(settings.intervalMinutes)
            choices.sort()
        }
        for minutes in choices {
            let item = actionItem(String(format: L("Every %d min"), minutes), #selector(selectInterval(_:)))
            item.tag = minutes
            item.state = minutes == settings.intervalMinutes ? .on : .off
            intervalMenu.addItem(item)
        }
        interval.submenu = intervalMenu
        menu.addItem(interval)

        let skip = actionItem(L("Skip While Audio Is Playing"), #selector(toggleSkipWhilePlaying))
        skip.state = settings.skipWhilePlaying ? .on : .off
        menu.addItem(skip)

        let wake = actionItem(L("Reset After Waking from Sleep"), #selector(toggleResetOnWake))
        wake.state = settings.resetOnWake ? .on : .off
        menu.addItem(wake)

        let devices = NSMenuItem(title: L("Auto-Reset Devices"), action: nil, keyEquivalent: "")
        devices.submenu = buildDevicesMenu()
        menu.addItem(devices)

        menu.addItem(.separator())

        let login = actionItem(L("Launch at Login"), #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)

        menu.addItem(.separator())

        menu.addItem(infoItem(currentOutputText()))
        menu.addItem(infoItem(lastResultText()))

        menu.addItem(.separator())
        menu.addItem(actionItem(L("Open GitHub Page…"), #selector(openRepository)))
        menu.addItem(infoItem("\(AppInfo.name) \(AppInfo.version)"))
        let quit = actionItem(String(format: L("Quit %@"), AppInfo.name), #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    /// One checkable item per external output device. Every device is checked
    /// (included) by default; excluded devices that are not connected right now
    /// are still listed so they can be included again.
    private func buildDevicesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let connected = AudioSystem.outputDevices().filter { !$0.isBuiltIn }
        let connectedUIDs = Set(connected.map(\.uid))
        let disconnectedExcluded = settings.excludedDevices
            .filter { !connectedUIDs.contains($0.key) }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }

        if connected.isEmpty, disconnectedExcluded.isEmpty {
            menu.addItem(infoItem(L("No external output devices")))
            return menu
        }

        for device in connected {
            menu.addItem(deviceItem(title: device.name, uid: device.uid, name: device.name))
        }
        if !disconnectedExcluded.isEmpty {
            if !connected.isEmpty { menu.addItem(.separator()) }
            for (uid, name) in disconnectedExcluded {
                menu.addItem(deviceItem(title: String(format: L("%@ (not connected)"), name), uid: uid, name: name))
            }
        }
        menu.addItem(.separator())
        menu.addItem(infoItem(L("Unchecked devices are only reset by clicking.")))
        return menu
    }

    private func deviceItem(title: String, uid: String, name: String) -> NSMenuItem {
        let item = actionItem(title, #selector(toggleDeviceAutoReset(_:)))
        item.representedObject = [uid, name]
        item.state = settings.isAutoResetEnabled(for: uid) ? .on : .off
        return item
    }

    private func currentOutputText() -> String {
        guard let output = AudioSystem.defaultDevice(.output) else { return L("Output: none") }
        if !output.isBuiltIn, !settings.isAutoResetEnabled(for: output.uid) {
            return String(format: L("Output: %@ (auto-reset off)"), output.name)
        }
        return String(format: L("Output: %@"), output.name)
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func lastResultText() -> String {
        guard let lastResult else { return L("Not run yet") }
        let time = DateFormatter.localizedString(from: lastResult.date, dateStyle: .none, timeStyle: .short)
        return String(format: L("Last run %@: %@"), time, localizedDescription(of: lastResult.outcome))
    }

    private func localizedDescription(of outcome: ResetOutcome) -> String {
        switch outcome {
        case let .reset(device, _, stoppedAfter):
            return String(format: L(stoppedAfter == nil ? "Reset %@ (device stayed busy)" : "Reset %@"), device)
        case .skippedBuiltIn: return L("Skipped (built-in output)")
        case .skippedPlaying: return L("Skipped (audio playing)")
        case .skippedExcluded: return L("Skipped (auto-reset off for this device)")
        case let .failed(failure):
            switch failure {
            case .noOutputDevice: return L("Failed: no output device")
            case .noIntermediateDevice: return L("Failed: no other output device")
            case let .couldNotSwitch(name, _): return String(format: L("Failed: could not switch to %@"), name)
            case let .deviceDisappeared(name): return String(format: L("Failed: %@ disappeared"), name)
            case let .couldNotSwitchBack(name): return String(format: L("Failed: could not switch back to %@"), name)
            }
        }
    }

    // MARK: Actions

    @objc private func resetNow() {
        runReset(trigger: .manual)
    }

    @objc private func togglePeriodicReset() {
        settings.periodicResetEnabled.toggle()
        rescheduleTimer()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        settings.intervalMinutes = sender.tag
        rescheduleTimer()
    }

    @objc private func toggleSkipWhilePlaying() {
        settings.skipWhilePlaying.toggle()
    }

    @objc private func toggleResetOnWake() {
        settings.resetOnWake.toggle()
    }

    @objc private func toggleDeviceAutoReset(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        let (uid, name) = (payload[0], payload[1])
        settings.setAutoReset(!settings.isAutoResetEnabled(for: uid), uid: uid, name: name)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change Launch at Login")
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Resetting

    private func runReset(trigger: ResetTrigger) {
        guard !isResetting else { return }
        isResetting = true
        setIcon(.busy)
        Resetter.shared.reset(trigger: trigger, options: settings.resetOptions) { [weak self] result in
            guard let self else { return }
            self.isResetting = false
            self.lastResult = result
            if result.outcome.isFailure {
                self.flashIcon(.failed)
            } else {
                self.setIcon(.idle)
            }
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.periodicResetEnabled else { return }

        let interval = TimeInterval(settings.intervalMinutes * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.runReset(trigger: .scheduled)
        }
        timer.tolerance = min(60, interval * 0.1)
        // .common keeps the timer firing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func systemDidWake(_ notification: Notification) {
        guard settings.resetOnWake else { return }
        // Give USB devices a moment to come back before touching them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.settings.resetOnWake else { return }
            self.runReset(trigger: .wake)
        }
    }
}
