import Foundation

struct PreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfig() -> RestConfig {
        RestConfig(
            workSeconds: TimeInterval(minutes("workMinutes", default: RestConfig.defaultWorkMinutes, max: 180) * 60),
            breakSeconds: TimeInterval(minutes("breakMinutes", default: RestConfig.defaultBreakMinutes, max: 60) * 60),
            snoozeSeconds: TimeInterval(minutes("snoozeMinutes", default: RestConfig.defaultSnoozeMinutes, max: 60) * 60),
            idlePauseSeconds: TimeInterval(minutes("idlePauseMinutes", default: RestConfig.defaultIdlePauseMinutes, max: 60) * 60),
            sessionResetSeconds: TimeInterval(minutes("sessionResetMinutes", default: RestConfig.defaultSessionResetMinutes, max: 240) * 60)
        )
    }

    func saveConfig(_ config: RestConfig) {
        defaults.set(max(1, Int(config.workSeconds / 60)), forKey: "workMinutes")
        defaults.set(max(1, Int(config.breakSeconds / 60)), forKey: "breakMinutes")
        defaults.set(max(1, Int(config.snoozeSeconds / 60)), forKey: "snoozeMinutes")
        defaults.set(max(1, Int(config.idlePauseSeconds / 60)), forKey: "idlePauseMinutes")
        defaults.set(max(1, Int(config.sessionResetSeconds / 60)), forKey: "sessionResetMinutes")
    }

    func loadSnapshot(now: Date) -> RestSnapshot {
        guard let data = defaults.data(forKey: "sessionJSON"),
              let saved = try? JSONDecoder().decode(PersistedSession.self, from: data)
        else {
            return RestSnapshot(phase: .working, activeSeconds: 0, remindersPaused: false, lastTick: now)
        }
        return RestSnapshot.restored(saved, now: now)
    }

    func saveSnapshot(_ snapshot: RestSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot.persisted()) else { return }
        defaults.set(data, forKey: "sessionJSON")
    }

    var didShowWelcome: Bool {
        get { defaults.bool(forKey: "didShowWelcome") }
        nonmutating set { defaults.set(newValue, forKey: "didShowWelcome") }
    }

    private func minutes(_ key: String, default defaultValue: Int, max maxValue: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return min(max(defaults.integer(forKey: key), 1), maxValue)
    }
}
