import AppKit

enum RestPanelContent: Equatable {
    case prompt(used: TimeInterval, breakLength: TimeInterval, snoozeLength: TimeInterval)
    case resting(remaining: TimeInterval)
    case finished
}

final class RestPanelController: NSObject {
    var onStartBreak: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    var onEndEarly: (() -> Void)?
    var onContinue: (() -> Void)?
    var onHideRest: (() -> Void)?

    private let panel: RestWindow
    private let card: CardView
    private let stack: NSStackView
    private let eyebrow = PassThroughLabel()
    private let titleLabel = PassThroughLabel()
    private let detailLabel = PassThroughLabel()
    private let primaryButton = AccentButton()
    private let snoozeButton = QuietButton()
    private let skipButton = QuietButton()
    private let secondaryRow = NSStackView()
    private let closeButton = QuietButton()
    private var mode: Mode = .prompt
    private var lastHeight: CGFloat = 0

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }

    override init() {
        panel = RestWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        card = CardView(frame: panel.contentView?.bounds ?? .zero)
        stack = NSStackView()
        super.init()

        panel.title = "休息提醒"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.onEscape = { [weak self] in self?.dismiss() }

        card.frame = panel.contentRect(forFrameRect: panel.frame)
        card.autoresizingMask = [.width, .height]
        panel.contentView = card

        eyebrow.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        eyebrow.textColor = Palette.eyebrow
        titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
        titleLabel.textColor = Palette.title
        titleLabel.maximumNumberOfLines = 1
        detailLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        detailLabel.textColor = Palette.body
        detailLabel.maximumNumberOfLines = 3
        detailLabel.cell?.wraps = true
        detailLabel.preferredMaxLayoutWidth = Metrics.contentWidth

        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        primaryButton.widthAnchor.constraint(equalToConstant: Metrics.contentWidth).isActive = true
        primaryButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

        snoozeButton.target = self
        snoozeButton.action = #selector(snoozeClicked)
        skipButton.target = self
        skipButton.action = #selector(skipClicked)

        secondaryRow.orientation = .horizontal
        secondaryRow.alignment = .centerY
        secondaryRow.spacing = 22
        secondaryRow.addArrangedSubview(snoozeButton)
        secondaryRow.addArrangedSubview(skipButton)

        closeButton.setLabel("×")
        closeButton.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.setAccessibilityLabel("关闭")
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(eyebrow)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(primaryButton)
        stack.addArrangedSubview(secondaryRow)
        stack.setCustomSpacing(6, after: eyebrow)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(20, after: detailLabel)
        stack.setCustomSpacing(8, after: primaryButton)

        card.addSubview(stack)
        card.addSubview(closeButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Metrics.side),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Metrics.side),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func present(_ content: RestPanelContent) {
        render(content)
        guard !panel.isVisible else { return }
        placeOnActiveScreen()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func render(_ content: RestPanelContent) {
        switch content {
        case .prompt(let used, let breakLength, let snoozeLength):
            mode = .prompt
            setEyebrow("该休息了")
            titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
            titleLabel.stringValue = "离开屏幕"
            detailLabel.stringValue = "已经累计使用 \(Format.duration(used))。\n看向远处，站起来活动大约 \(max(1, Int(breakLength / 60))) 分钟。"
            primaryButton.setLabel("开始休息")
            snoozeButton.setLabel("稍后 \(max(1, Int(snoozeLength / 60))) 分钟")
            skipButton.setLabel("跳过这次")
            secondaryRow.isHidden = false
        case .resting(let remaining):
            mode = .resting
            setEyebrow("休息中")
            titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 56, weight: .light)
            titleLabel.stringValue = Format.clock(remaining)
            detailLabel.stringValue = "看看远处，或者离开椅子走一走。"
            primaryButton.setLabel("提前结束")
            secondaryRow.isHidden = true
        case .finished:
            mode = .finished
            setEyebrow("休息结束")
            titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
            titleLabel.stringValue = "可以继续了"
            detailLabel.stringValue = "这一轮已经清零，菜单栏会继续计时。"
            primaryButton.setLabel("继续工作")
            secondaryRow.isHidden = true
        }
        resizeIfNeeded()
    }

    private func setEyebrow(_ text: String) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        eyebrow.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: Palette.eyebrow,
            .kern: 1.2,
            .paragraphStyle: style,
        ])
    }

    private func resizeIfNeeded() {
        card.layoutSubtreeIfNeeded()
        let height = max(200, stack.fittingSize.height + 28 + 24)
        guard abs(height - lastHeight) > 1 else { return }
        let old = panel.frame
        let originY = old.height == 0 ? old.origin.y : old.midY - height / 2
        let frame = NSRect(x: old.origin.x, y: originY, width: Metrics.width, height: height)
        panel.setFrame(frame, display: true)
        lastHeight = height
    }

    private func placeOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    @objc private func primaryClicked() {
        switch mode {
        case .prompt: onStartBreak?()
        case .resting: onEndEarly?()
        case .finished: onContinue?()
        }
    }

    @objc private func snoozeClicked() { onSnooze?() }
    @objc private func skipClicked() { onSkip?() }

    @objc private func closeClicked() { dismiss() }

    private func dismiss() {
        switch mode {
        case .prompt: onSnooze?()
        case .resting: onHideRest?()
        case .finished: onContinue?()
        }
    }

    private enum Mode {
        case prompt
        case resting
        case finished
    }
}

private enum Metrics {
    static let width: CGFloat = 420
    static let side: CGFloat = 28
    static var contentWidth: CGFloat { width - side * 2 }
}

private enum Palette {
    static let card = NSColor(srgbRed: 0.141, green: 0.122, blue: 0.102, alpha: 1)
    static let title = NSColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1)
    static let body = NSColor(srgbRed: 0.718, green: 0.678, blue: 0.624, alpha: 1)
    static let eyebrow = NSColor(srgbRed: 0.878, green: 0.710, blue: 0.416, alpha: 1)
    static let accent = NSColor(srgbRed: 0.878, green: 0.710, blue: 0.416, alpha: 1)
    static let accentPressed = NSColor(srgbRed: 0.745, green: 0.569, blue: 0.275, alpha: 1)
    static let accentText = NSColor(srgbRed: 0.165, green: 0.129, blue: 0.094, alpha: 1)
    static let quiet = NSColor(srgbRed: 0.788, green: 0.733, blue: 0.659, alpha: 1)
    static let quietPressed = NSColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1)
}

private final class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        Palette.card.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class PassThroughLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        lineBreakMode = .byWordWrapping
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class AccentButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setLabel(_ text: String) {
        title = text
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: Palette.accentText,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = isHighlighted ? Palette.accentPressed : Palette.accent
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let text = attributedTitle
        let size = text.size()
        text.draw(in: NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2 - 1,
            width: size.width,
            height: size.height
        ))
    }
}

private final class QuietButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setLabel(_ text: String) {
        title = text
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Palette.quiet,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            Palette.quietPressed.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let text = attributedTitle
        let size = text.size()
        let color = isHighlighted ? Palette.quietPressed : Palette.quiet
        let drawn = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ])
        drawn.draw(in: NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2 - 1,
            width: size.width,
            height: size.height
        ))
    }

    override var intrinsicContentSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: size.width + 16, height: max(28, size.height + 8))
    }
}

private final class RestWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
