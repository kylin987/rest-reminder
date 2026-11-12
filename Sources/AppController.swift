import AppKit
import ServiceManagement

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let launch: LaunchOptions
    private let store = PreferencesStore()
    private let panel = RestPanelController()
    private var config: RestConfig
    private var snapshot: RestSnapshot
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var overlay: Overlay?
    private var lastPersisted: PersistedSession?
    private var settingsController: SettingsWindowController?
    private var didScheduleScreenshot = false

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "正在计时", action: nil, keyEquivalent: "")
    private let restNowItem = NSMenuItem(title: "立即休息", action: #selector(restNow), keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "重新计时", action: #selector(resetSession), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停提醒", action: #selector(togglePause), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
    private let launchItem = NSMenuItem(title: "登录时打开", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "退出休息提醒", action: #selector(quit), keyEquivalent: "q")

    init(launch: LaunchOptions) {
        self.launch = launch
        let now = Date()
        let loaded = store.loadConfig()
        config = launch.apply(to: loaded)
        snapshot = launch.isEphemeral
            ? RestSnapshot(phase: .working, activeSeconds: 0, remindersPaused: false, lastTick: now)
            : store.loadSnapshot(now: now)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "统计键鼠使用时间并提醒休息"
        )
        buildMenu()
        wirePanel()
        refreshStatus(now: Date(), idle: IdleSensor.secondsSinceLastInput())

        if launch.demo != nil {
            showDemo()
            scheduleScreenshotIfNeeded()
            if launch.screenshotURL == nil {
                startTimer()
            }
            return
        }

        let now = Date()
        let idle = IdleSensor.secondsSinceLastInput()
        let result = SessionEngine.tick(
            snapshot: snapshot,
            now: now,
            idleSeconds: idle,
            config: config,
            allowsAbsenceResolution: true
        )
        apply(result, now: now, idle: idle)
        if case .due = snapshot.phase, !snapshot.remindersPaused, overlay == nil {
            showPrompt(playSound: !launch.isEphemeral)
        } else if case .resting = snapshot.phase, overlay == nil {
            showResting()
        }
        startTimer()
        DispatchQueue.main.async { [weak self] in
            self?.showWelcomeIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        persist(force: true)
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus(now: Date(), idle: IdleSensor.secondsSinceLastInput())
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem.isEnabled = false
        for item in [restNowItem, resetItem, pauseItem, settingsItem, launchItem, quitItem] {
            item.target = self
        }
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(restNowItem)
        menu.addItem(resetItem)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "休息提醒") {
                let symbol = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) ?? image
                symbol.isTemplate = true
                button.image = symbol
                button.imagePosition = .imageLeading
            }
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
    }

    private func wirePanel() {
        panel.onStartBreak = { [weak self] in self?.startBreak() }
        panel.onSnooze = { [weak self] in self?.snooze() }
        panel.onSkip = { [weak self] in self?.resetFromPrompt() }
        panel.onEndEarly = { [weak self] in self?.endBreakEarly() }
        panel.onContinue = { [weak self] in self?.finishAndHide() }
        panel.onHideRest = { [weak self] in self?.panel.hide() }
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        let idle = IdleSensor.secondsSinceLastInput()
        let result = SessionEngine.tick(
            snapshot: snapshot,
            now: now,
            idleSeconds: idle,
            config: config,
            allowsAbsenceResolution: launch.demo == nil
        )
        apply(result, now: now, idle: idle)
    }

    private func apply(_ result: RestTickResult, now: Date, idle: TimeInterval) {
        snapshot = result.snapshot
        if result.becameDue {
            showPrompt(playSound: !launch.isEphemeral)
        } else if result.breakFinished {
            overlay = .finished(until: now.addingTimeInterval(4))
            panel.present(.finished)
        } else if result.hidePrompt {
            overlay = nil
            panel.hide()
        } else if case .finished(let until) = overlay, now >= until {
            overlay = nil
            panel.hide()
        } else if panel.isVisible {
            switch snapshot.phase {
            case .due:
                panel.present(promptContent())
            case .resting(let until):
                panel.present(.resting(remaining: until.timeIntervalSince(now)))
            default:
                break
            }
        }
        refreshStatus(now: now, idle: idle)
        persist(force: false)
        if launch.logTicks {
            fputs(
                String(format: "tick phase=%@ active=%.1f idle=%.1f due=%@\n",
                       phaseName(snapshot.phase),
                       snapshot.activeSeconds,
                       idle,
                       result.becameDue ? "yes" : "no"),
                stdout
            )
            fflush(stdout)
        }
    }

    private func showPrompt(playSound: Bool) {
        overlay = .prompt
        if playSound {
            NSSound(named: "Glass")?.play()
        }
        panel.present(promptContent())
    }

    private func showResting() {
        guard case .resting(let until) = snapshot.phase else { return }
        overlay = .resting
        panel.present(.resting(remaining: until.timeIntervalSince(Date())))
    }

    private func promptContent() -> RestPanelContent {
        .prompt(used: snapshot.activeSeconds, breakLength: config.breakSeconds, snoozeLength: config.snoozeSeconds)
    }

    private func startBreak() {
        let now = Date()
        snapshot = SessionEngine.handle(.startBreak, snapshot: snapshot, now: now, config: config)
        showResting()
        refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
        persist(force: true)
    }

    private func snooze() {
        let now = Date()
        snapshot = SessionEngine.handle(.snooze, snapshot: snapshot, now: now, config: config)
        overlay = nil
        panel.hide()
        refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
        persist(force: true)
    }

    private func resetFromPrompt() {
        let now = Date()
        snapshot = SessionEngine.handle(.resetSession, snapshot: snapshot, now: now, config: config)
        overlay = nil
        panel.hide()
        refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
        persist(force: true)
    }

    private func endBreakEarly() {
        let now = Date()
        snapshot = SessionEngine.handle(.resetSession, snapshot: snapshot, now: now, config: config)
        overlay = .finished(until: now.addingTimeInterval(4))
        panel.present(.finished)
        refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
        persist(force: true)
    }

    private func finishAndHide() {
        overlay = nil
        panel.hide()
    }

    private func refreshStatus(now: Date, idle: TimeInterval) {
        let title = Format.menuTitle(snapshot: snapshot, now: now)
        let line = Format.statusLine(snapshot: snapshot, idleSeconds: idle, config: config, now: now)
        statusItem.button?.title = title
        statusItem.button?.toolTip = line
        statusMenuItem.title = line
        pauseItem.title = snapshot.remindersPaused ? "继续提醒" : "暂停提醒"
        switch snapshot.phase {
        case .resting:
            restNowItem.title = "显示休息倒计时"
        case .due:
            restNowItem.title = "显示休息窗口"
        default:
            restNowItem.title = "立即休息"
        }
    }

    private func showWelcomeIfNeeded() {
        guard launch.demo == nil, !launch.isEphemeral, !store.didShowWelcome else { return }
        store.didShowWelcome = true
        let alert = NSAlert()
        alert.messageText = "休息提醒已经在菜单栏"
        alert.informativeText = "杯子旁边是累计使用时间。键鼠在动就会计时，连续 \(Int(config.idlePauseSeconds / 60)) 分钟没操作会暂停，离开 \(Int(config.sessionResetSeconds / 60)) 分钟会从头计算。默认满 \(Int(config.workSeconds / 60)) 分钟提醒一次。可以在菜单里改时间，或点「立即休息」先看一眼。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate()
        alert.window.level = .statusBar
        alert.runModal()
    }

    private func showDemo() {
        switch launch.demo {
        case .due:
            snapshot.phase = .due
            snapshot.activeSeconds = config.workSeconds
            showPrompt(playSound: false)
        case .rest:
            snapshot.phase = .resting(until: Date().addingTimeInterval(125))
            showResting()
        case .done:
            overlay = .finished(until: Date().addingTimeInterval(60))
            panel.present(.finished)
        case .settings:
            openSettings()
        case nil:
            break
        }
        refreshStatus(now: Date(), idle: 0)
    }

    private func scheduleScreenshotIfNeeded() {
        guard let url = launch.screenshotURL, !didScheduleScreenshot else { return }
        didScheduleScreenshot = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let window: NSWindow
            if self.launch.demo == .settings, let settingsWindow = self.settingsController?.window {
                window = settingsWindow
            } else {
                window = self.panel.window
            }
            Self.capture(window, to: url)
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else {
            fputs("没有可截取的窗口\n", stderr)
            exit(1)
        }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let windowID = CGWindowID(window.windowNumber)
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]) {
                do {
                    try data.write(to: url)
                    return
                } catch {
                    fputs("写入失败 \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("截图失败\n", stderr)
            exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("编码失败\n", stderr)
            exit(1)
        }
        do {
            try data.write(to: url)
        } catch {
            fputs("写入失败 \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func persist(force: Bool) {
        guard !launch.isEphemeral else { return }
        var saved = snapshot.persisted()
        saved.activeSeconds = saved.activeSeconds.rounded(.down)
        if !force, saved == lastPersisted { return }
        store.saveSnapshot(snapshot)
        lastPersisted = saved
    }

    private func openSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController(config: config)
            controller.onChange = { [weak self] newConfig in
                self?.updateConfig(newConfig)
            }
            settingsController = controller
        }
        NSApp.activate()
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func updateConfig(_ newConfig: RestConfig) {
        config = newConfig
        if !launch.isEphemeral {
            store.saveConfig(newConfig)
        }
        if case .due = snapshot.phase, snapshot.activeSeconds < config.workSeconds {
            let now = Date()
            snapshot.phase = .working
            snapshot.lastTick = now
            overlay = nil
            panel.hide()
            persist(force: true)
        }
        refreshStatus(now: Date(), idle: IdleSensor.secondsSinceLastInput())
    }

    private func phaseName(_ phase: RestPhase) -> String {
        switch phase {
        case .working: return "working"
        case .due: return "due"
        case .snoozed: return "snoozed"
        case .resting: return "resting"
        }
    }

    @objc private func restNow() {
        switch snapshot.phase {
        case .resting:
            showResting()
        case .due:
            showPrompt(playSound: false)
        default:
            let now = Date()
            snapshot = SessionEngine.handle(.promptNow, snapshot: snapshot, now: now, config: config)
            showPrompt(playSound: !launch.isEphemeral)
            refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
            persist(force: true)
        }
    }

    @objc private func resetSession() {
        resetFromPrompt()
    }

    @objc private func togglePause() {
        let now = Date()
        if snapshot.remindersPaused {
            snapshot = SessionEngine.handle(.resumeReminders, snapshot: snapshot, now: now, config: config)
            if case .due = snapshot.phase {
                showPrompt(playSound: false)
            } else if case .resting = snapshot.phase {
                showResting()
            }
        } else {
            snapshot = SessionEngine.handle(.pauseReminders, snapshot: snapshot, now: now, config: config)
            overlay = nil
            panel.hide()
        }
        refreshStatus(now: now, idle: IdleSensor.secondsSinceLastInput())
        persist(force: true)
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "还不能设为登录时打开"
            alert.informativeText = "请把「休息提醒」留在「应用程序」文件夹里，并在系统设置的登录项中允许它。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private enum Overlay: Equatable {
    case prompt
    case resting
    case finished(until: Date)
}
