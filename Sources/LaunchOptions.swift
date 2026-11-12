import Foundation

struct LaunchOptions {
    enum Demo: String {
        case due
        case rest
        case done
        case settings
    }

    var printIdle = false
    var logTicks = false
    var demo: Demo?
    var screenshotURL: URL?
    var workSeconds: TimeInterval?
    var breakSeconds: TimeInterval?
    var snoozeSeconds: TimeInterval?
    var idlePauseSeconds: TimeInterval?
    var sessionResetSeconds: TimeInterval?

    var isEphemeral: Bool {
        demo != nil || screenshotURL != nil || workSeconds != nil || breakSeconds != nil || snoozeSeconds != nil
            || idlePauseSeconds != nil || sessionResetSeconds != nil || logTicks
    }

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var iterator = arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--print-idle":
                options.printIdle = true
            case "--log-ticks":
                options.logTicks = true
            case "--demo":
                if let raw = iterator.next() {
                    options.demo = Demo(rawValue: raw)
                }
            case "--screenshot":
                if let path = iterator.next() {
                    options.screenshotURL = URL(fileURLWithPath: path)
                }
            case "--work-seconds":
                options.workSeconds = iterator.next().flatMap(Double.init)
            case "--break-seconds":
                options.breakSeconds = iterator.next().flatMap(Double.init)
            case "--snooze-seconds":
                options.snoozeSeconds = iterator.next().flatMap(Double.init)
            case "--idle-seconds":
                options.idlePauseSeconds = iterator.next().flatMap(Double.init)
            case "--reset-seconds":
                options.sessionResetSeconds = iterator.next().flatMap(Double.init)
            default:
                continue
            }
        }
        return options
    }

    func apply(to config: RestConfig) -> RestConfig {
        var config = config
        if let workSeconds { config.workSeconds = workSeconds }
        if let breakSeconds { config.breakSeconds = breakSeconds }
        if let snoozeSeconds { config.snoozeSeconds = snoozeSeconds }
        if let idlePauseSeconds { config.idlePauseSeconds = idlePauseSeconds }
        if let sessionResetSeconds { config.sessionResetSeconds = sessionResetSeconds }
        return config
    }
}
