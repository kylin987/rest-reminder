import Foundation

struct RestConfig: Equatable {
    var workSeconds: TimeInterval
    var breakSeconds: TimeInterval
    var snoozeSeconds: TimeInterval
    var idlePauseSeconds: TimeInterval
    var sessionResetSeconds: TimeInterval

    static let defaultWorkMinutes = 45
    static let defaultBreakMinutes = 5
    static let defaultSnoozeMinutes = 5
    static let defaultIdlePauseMinutes = 3
    static let defaultSessionResetMinutes = 15

    static let `default` = RestConfig(
        workSeconds: TimeInterval(defaultWorkMinutes * 60),
        breakSeconds: TimeInterval(defaultBreakMinutes * 60),
        snoozeSeconds: TimeInterval(defaultSnoozeMinutes * 60),
        idlePauseSeconds: TimeInterval(defaultIdlePauseMinutes * 60),
        sessionResetSeconds: TimeInterval(defaultSessionResetMinutes * 60)
    )
}

enum RestPhase: Equatable {
    case working
    case due
    case snoozed(until: Date)
    case resting(until: Date)
}

struct RestSnapshot: Equatable {
    var phase: RestPhase
    var activeSeconds: TimeInterval
    var remindersPaused: Bool
    var lastTick: Date
}

struct PersistedSession: Codable, Equatable {
    var activeSeconds: Double
    var phase: String
    var phaseUntilEpoch: Double?
    var remindersPaused: Bool
}

enum RestCommand: Equatable {
    case startBreak
    case snooze
    case resetSession
    case pauseReminders
    case resumeReminders
    case promptNow
}

struct RestTickResult: Equatable {
    var snapshot: RestSnapshot
    var becameDue: Bool = false
    var breakFinished: Bool = false
    var hidePrompt: Bool = false
}

enum SessionEngine {
    /// One stalled timer wake should not dump a whole afternoon into the counter.
    static let maxActiveStep: TimeInterval = 120

    static func tick(
        snapshot: RestSnapshot,
        now: Date,
        idleSeconds: TimeInterval,
        config: RestConfig,
        allowsAbsenceResolution: Bool = true
    ) -> RestTickResult {
        var snap = snapshot
        let step = min(max(0, now.timeIntervalSince(snap.lastTick)), maxActiveStep)
        snap.lastTick = now

        if snap.remindersPaused {
            if case .resting(let until) = snap.phase, now >= until {
                snap.phase = .working
                snap.activeSeconds = 0
                return RestTickResult(snapshot: snap, hidePrompt: true)
            }
            if case .snoozed(let until) = snap.phase, now >= until {
                snap.phase = .due
            }
            return RestTickResult(snapshot: snap)
        }

        switch snap.phase {
        case .working:
            if allowsAbsenceResolution, idleSeconds >= config.sessionResetSeconds {
                snap.activeSeconds = 0
                return RestTickResult(snapshot: snap)
            }
            if idleSeconds < config.idlePauseSeconds {
                snap.activeSeconds += step
                if snap.activeSeconds >= config.workSeconds {
                    snap.activeSeconds = config.workSeconds
                    snap.phase = .due
                    return RestTickResult(snapshot: snap, becameDue: true)
                }
            }
            return RestTickResult(snapshot: snap)

        case .due:
            // 立即休息会在还没累计满时进入 due。没满不能在下一秒被清掉。
            // 调高工作时长时由设置界面单独收起弹窗。
            if allowsAbsenceResolution, idleSeconds >= config.breakSeconds {
                snap.phase = .working
                snap.activeSeconds = 0
                return RestTickResult(snapshot: snap, hidePrompt: true)
            }
            return RestTickResult(snapshot: snap)

        case .snoozed(let until):
            if allowsAbsenceResolution, idleSeconds >= config.sessionResetSeconds {
                snap.phase = .working
                snap.activeSeconds = 0
                return RestTickResult(snapshot: snap, hidePrompt: true)
            }
            if now >= until {
                snap.phase = .due
                return RestTickResult(snapshot: snap, becameDue: true)
            }
            return RestTickResult(snapshot: snap)

        case .resting(let until):
            if now >= until {
                snap.phase = .working
                snap.activeSeconds = 0
                return RestTickResult(snapshot: snap, breakFinished: true)
            }
            return RestTickResult(snapshot: snap)
        }
    }

    static func handle(
        _ command: RestCommand,
        snapshot: RestSnapshot,
        now: Date,
        config: RestConfig
    ) -> RestSnapshot {
        var snap = snapshot
        snap.lastTick = now
        switch command {
        case .startBreak:
            snap.phase = .resting(until: now.addingTimeInterval(config.breakSeconds))
            snap.remindersPaused = false
        case .snooze:
            snap.phase = .snoozed(until: now.addingTimeInterval(config.snoozeSeconds))
        case .resetSession:
            snap.phase = .working
            snap.activeSeconds = 0
        case .pauseReminders:
            snap.remindersPaused = true
        case .resumeReminders:
            snap.remindersPaused = false
        case .promptNow:
            if case .resting = snap.phase {
                break
            }
            snap.phase = .due
            snap.remindersPaused = false
        }
        return snap
    }
}

extension RestSnapshot {
    func persisted() -> PersistedSession {
        let name: String
        let until: Date?
        switch phase {
        case .working:
            name = "working"
            until = nil
        case .due:
            name = "due"
            until = nil
        case .snoozed(let date):
            name = "snoozed"
            until = date
        case .resting(let date):
            name = "resting"
            until = date
        }
        return PersistedSession(
            activeSeconds: activeSeconds,
            phase: name,
            phaseUntilEpoch: until?.timeIntervalSince1970,
            remindersPaused: remindersPaused
        )
    }

    static func restored(_ saved: PersistedSession, now: Date) -> RestSnapshot {
        let until = saved.phaseUntilEpoch.map(Date.init(timeIntervalSince1970:))
        switch saved.phase {
        case "due":
            return RestSnapshot(
                phase: .due,
                activeSeconds: max(0, saved.activeSeconds),
                remindersPaused: saved.remindersPaused,
                lastTick: now
            )
        case "snoozed":
            if let until, until > now {
                return RestSnapshot(
                    phase: .snoozed(until: until),
                    activeSeconds: max(0, saved.activeSeconds),
                    remindersPaused: saved.remindersPaused,
                    lastTick: now
                )
            }
            return RestSnapshot(
                phase: .due,
                activeSeconds: max(0, saved.activeSeconds),
                remindersPaused: saved.remindersPaused,
                lastTick: now
            )
        case "resting":
            if let until, until > now {
                return RestSnapshot(
                    phase: .resting(until: until),
                    activeSeconds: max(0, saved.activeSeconds),
                    remindersPaused: saved.remindersPaused,
                    lastTick: now
                )
            }
            return RestSnapshot(phase: .working, activeSeconds: 0, remindersPaused: saved.remindersPaused, lastTick: now)
        default:
            return RestSnapshot(
                phase: .working,
                activeSeconds: max(0, saved.activeSeconds),
                remindersPaused: saved.remindersPaused,
                lastTick: now
            )
        }
    }
}
