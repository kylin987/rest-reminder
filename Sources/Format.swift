import Foundation

enum Format {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds / 60).rounded(.down)))
        if total < 60 { return "\(total) 分钟" }
        let hours = total / 60
        let remain = total % 60
        if remain == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(remain) 分钟"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(0, Int(seconds.rounded(.down)))) 秒"
        }
        return minutes(seconds)
    }

    static func menuTitle(snapshot: RestSnapshot, now: Date) -> String {
        if snapshot.remindersPaused { return "暂停" }
        switch snapshot.phase {
        case .working:
            let seconds = snapshot.activeSeconds
            if seconds < 60 { return "\(Int(seconds))s" }
            let minutes = Int(seconds / 60)
            if minutes < 60 { return "\(minutes)m" }
            return "\(minutes / 60)h\(minutes % 60)m"
        case .due:
            return "休息"
        case .snoozed:
            return "稍后"
        case .resting(let until):
            return "休\(clock(until.timeIntervalSince(now)))"
        }
    }

    static func statusLine(
        snapshot: RestSnapshot,
        idleSeconds: TimeInterval,
        config: RestConfig,
        now: Date
    ) -> String {
        if snapshot.remindersPaused {
            return "提醒已暂停，已累计 \(duration(snapshot.activeSeconds))"
        }
        switch snapshot.phase {
        case .working:
            if idleSeconds >= config.sessionResetSeconds {
                return "离开较久，这一轮已重新开始"
            }
            if idleSeconds >= config.idlePauseSeconds {
                return "暂时离开，计时停在 \(duration(snapshot.activeSeconds))"
            }
            if snapshot.activeSeconds < 1 {
                return "正在计时，满 \(minutes(config.workSeconds)) 提醒"
            }
            return "已累计 \(duration(snapshot.activeSeconds))，满 \(minutes(config.workSeconds)) 提醒"
        case .due:
            return "该休息了，已累计 \(duration(snapshot.activeSeconds))"
        case .snoozed(let until):
            return "稍后提醒，还剩 \(clock(until.timeIntervalSince(now)))"
        case .resting(let until):
            return "休息中，还剩 \(clock(until.timeIntervalSince(now)))"
        }
    }
}
