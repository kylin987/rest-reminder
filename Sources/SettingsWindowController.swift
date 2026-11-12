import AppKit

final class SettingsWindowController: NSWindowController {
    var onChange: ((RestConfig) -> Void)?

    private let workStepper = NSStepper()
    private let breakStepper = NSStepper()
    private let snoozeStepper = NSStepper()
    private let idleStepper = NSStepper()
    private let resetStepper = NSStepper()
    private let workValue = NSTextField(labelWithString: "")
    private let breakValue = NSTextField(labelWithString: "")
    private let snoozeValue = NSTextField(labelWithString: "")
    private let idleValue = NSTextField(labelWithString: "")
    private let resetValue = NSTextField(labelWithString: "")

    convenience init(config: RestConfig) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "休息提醒设置"
        self.init(window: window)
        build(config)
        window.center()
    }

    private func build(_ config: RestConfig) {
        guard let content = window?.contentView else { return }

        configure(workStepper, value: config.workSeconds / 60, min: 5, max: 180)
        configure(breakStepper, value: config.breakSeconds / 60, min: 1, max: 60)
        configure(snoozeStepper, value: config.snoozeSeconds / 60, min: 1, max: 60)
        configure(idleStepper, value: config.idlePauseSeconds / 60, min: 1, max: 60)
        configure(resetStepper, value: config.sessionResetSeconds / 60, min: 2, max: 240)
        for value in [workValue, breakValue, snoozeValue, idleValue, resetValue] {
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.alignment = .right
            value.textColor = .labelColor
        }
        refreshLabels()
        syncResetFloor()

        let width: CGFloat = 460
        let rowHeight: CGFloat = 32
        let rows: [(String, NSTextField, NSStepper, String)] = [
            ("连续使用多久后提醒", workValue, workStepper, "键鼠累计活动达到这个时长就提醒。"),
            ("休息时长", breakValue, breakStepper, "休息窗口出现后直接开始的倒计时。"),
            ("稍后提醒", snoozeValue, snoozeStepper, "先关掉窗口，过这段时间再提醒。"),
            ("多久没操作就暂停", idleValue, idleStepper, "连续这么久没有键鼠操作，就先停下累计。"),
            ("离开多久就重新计时", resetValue, resetStepper, "离开超过这段时间，视为已经休息过，从 0 开始。"),
        ]
        let note = NSTextField(wrappingLabelWithString: "只看键鼠有没有在动，不记录你按了什么、点了哪里。暂停前累计的时间会留着；离开足够久，就视为这轮已经休息完。")
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        let noteHeight: CGFloat = 48
        let button = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefaults))
        button.bezelStyle = .rounded
        button.sizeToFit()
        let height = 16 + CGFloat(rows.count) * rowHeight + 12 + noteHeight + 14 + button.frame.height + 16
        window?.setContentSize(NSSize(width: width, height: height))

        var y = height - 12 - rowHeight
        for (title, value, stepper, tip) in rows {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.toolTip = tip
            label.frame = NSRect(x: 20, y: y, width: 250, height: rowHeight)
            stepper.sizeToFit()
            stepper.frame.origin = NSPoint(
                x: width - 20 - stepper.frame.width,
                y: y + (rowHeight - stepper.frame.height) / 2
            )
            value.frame = NSRect(x: stepper.frame.minX - 96, y: y, width: 88, height: rowHeight)
            content.addSubview(label)
            content.addSubview(value)
            content.addSubview(stepper)
            y -= rowHeight
        }

        note.frame = NSRect(x: 20, y: y - noteHeight + 8, width: width - 40, height: noteHeight)
        content.addSubview(note)
        button.frame.origin = NSPoint(x: 20, y: 16)
        content.addSubview(button)
    }

    func currentConfig() -> RestConfig {
        syncResetFloor()
        return RestConfig(
            workSeconds: workStepper.doubleValue * 60,
            breakSeconds: breakStepper.doubleValue * 60,
            snoozeSeconds: snoozeStepper.doubleValue * 60,
            idlePauseSeconds: idleStepper.doubleValue * 60,
            sessionResetSeconds: resetStepper.doubleValue * 60
        )
    }

    private func configure(_ stepper: NSStepper, value: Double, min: Double, max: Double) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.doubleValue = value
        stepper.target = self
        stepper.action = #selector(stepperChanged)
    }

    private func syncResetFloor() {
        let floor = idleStepper.doubleValue + 1
        resetStepper.minValue = floor
        if resetStepper.doubleValue < floor {
            resetStepper.doubleValue = floor
        }
    }

    private func refreshLabels() {
        workValue.stringValue = "\(workStepper.integerValue) 分钟"
        breakValue.stringValue = "\(breakStepper.integerValue) 分钟"
        snoozeValue.stringValue = "\(snoozeStepper.integerValue) 分钟"
        idleValue.stringValue = "\(idleStepper.integerValue) 分钟"
        resetValue.stringValue = "\(resetStepper.integerValue) 分钟"
    }

    @objc private func stepperChanged() {
        syncResetFloor()
        refreshLabels()
        onChange?(currentConfig())
    }

    @objc private func restoreDefaults() {
        let config = RestConfig.default
        workStepper.doubleValue = config.workSeconds / 60
        breakStepper.doubleValue = config.breakSeconds / 60
        snoozeStepper.doubleValue = config.snoozeSeconds / 60
        idleStepper.doubleValue = config.idlePauseSeconds / 60
        resetStepper.doubleValue = config.sessionResetSeconds / 60
        syncResetFloor()
        refreshLabels()
        onChange?(currentConfig())
    }
}
