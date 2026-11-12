import Foundation

func runSessionTests() {
var checks = 0
var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        failures += 1
        fputs("FAIL \(message)\n", stderr)
    }
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
let config = RestConfig(
    workSeconds: 100,
    breakSeconds: 20,
    snoozeSeconds: 15,
    idlePauseSeconds: 10,
    sessionResetSeconds: 30
)

func base(
    at date: Date,
    phase: RestPhase = .working,
    active: TimeInterval = 0,
    paused: Bool = false
) -> RestSnapshot {
    RestSnapshot(phase: phase, activeSeconds: active, remindersPaused: paused, lastTick: date)
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0), now: t0.addingTimeInterval(5), idleSeconds: 1, config: config)
    check(result.snapshot.activeSeconds == 5, "active time accumulates")
    check(result.snapshot.phase == .working, "stays working")
    check(!result.becameDue, "not due yet")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 40), now: t0.addingTimeInterval(5), idleSeconds: 10, config: config)
    check(result.snapshot.activeSeconds == 40, "idle at the pause threshold does not accumulate")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 40), now: t0.addingTimeInterval(5), idleSeconds: 15, config: config)
    check(result.snapshot.activeSeconds == 40, "pause band keeps the accumulated time")
    check(result.snapshot.phase == .working, "pause band stays working")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 40), now: t0.addingTimeInterval(5), idleSeconds: 30, config: config)
    check(result.snapshot.activeSeconds == 0, "long absence resets the session")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 95), now: t0.addingTimeInterval(5), idleSeconds: 1, config: config)
    check(result.becameDue, "crossing the limit becomes due")
    check(result.snapshot.phase == .due, "phase is due")
    check(result.snapshot.activeSeconds == 100, "active time caps at the work limit")
}

do {
    let due = base(at: t0, phase: .due, active: 100)
    let result = SessionEngine.tick(snapshot: due, now: t0.addingTimeInterval(1), idleSeconds: 1, config: config)
    check(!result.becameDue, "an existing prompt does not fire again")
    check(result.snapshot.phase == .due, "prompt stays up")
}

do {
    let longWork = RestConfig(
        workSeconds: 1000, breakSeconds: 20, snoozeSeconds: 15, idlePauseSeconds: 10, sessionResetSeconds: 30
    )
    let result = SessionEngine.tick(snapshot: base(at: t0), now: t0.addingTimeInterval(500), idleSeconds: 0, config: longWork)
    check(result.snapshot.activeSeconds == SessionEngine.maxActiveStep, "a stalled tick is capped")
    check(!result.becameDue, "the cap alone does not finish a long session")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 10), now: t0.addingTimeInterval(-4), idleSeconds: 0, config: config)
    check(result.snapshot.activeSeconds == 10, "a backwards clock does not add time")
}

do {
    let snoozed = base(at: t0, phase: .snoozed(until: t0.addingTimeInterval(10)), active: 100)
    let waiting = SessionEngine.tick(snapshot: snoozed, now: t0.addingTimeInterval(9), idleSeconds: 0, config: config)
    check(waiting.snapshot.phase == .snoozed(until: t0.addingTimeInterval(10)), "snooze waits")
    let due = SessionEngine.tick(snapshot: snoozed, now: t0.addingTimeInterval(10), idleSeconds: 0, config: config)
    check(due.becameDue && due.snapshot.phase == .due, "snooze expires into a prompt")
}

do {
    let snoozed = base(at: t0, phase: .snoozed(until: t0.addingTimeInterval(10)), active: 80)
    let result = SessionEngine.tick(snapshot: snoozed, now: t0.addingTimeInterval(2), idleSeconds: 30, config: config)
    check(result.hidePrompt && result.snapshot.phase == .working && result.snapshot.activeSeconds == 0, "leaving during snooze clears the round")
}

do {
    let resting = base(at: t0, phase: .resting(until: t0.addingTimeInterval(10)), active: 100)
    let ongoing = SessionEngine.tick(snapshot: resting, now: t0.addingTimeInterval(9), idleSeconds: 0, config: config)
    check(ongoing.snapshot.phase == .resting(until: t0.addingTimeInterval(10)) && !ongoing.breakFinished, "rest keeps counting down")
    let done = SessionEngine.tick(snapshot: resting, now: t0.addingTimeInterval(10), idleSeconds: 0, config: config)
    check(done.breakFinished && done.snapshot.phase == .working && done.snapshot.activeSeconds == 0, "finishing a rest resets the counter")
}

do {
    let due = base(at: t0, phase: .due, active: 100)
    let stay = SessionEngine.tick(snapshot: due, now: t0.addingTimeInterval(1), idleSeconds: 19, config: config)
    check(stay.snapshot.phase == .due && !stay.hidePrompt, "a short step away keeps the prompt")
    let left = SessionEngine.tick(snapshot: due, now: t0.addingTimeInterval(1), idleSeconds: 20, config: config)
    check(left.hidePrompt && left.snapshot.phase == .working && left.snapshot.activeSeconds == 0, "being away for the break clears the prompt")
}

do {
    let early = SessionEngine.handle(.promptNow, snapshot: base(at: t0, active: 30), now: t0, config: config)
    check(early.phase == .due && early.activeSeconds == 30, "rest now opens before the work limit")
    let result = SessionEngine.tick(snapshot: early, now: t0.addingTimeInterval(1), idleSeconds: 0, config: config)
    check(result.snapshot.phase == .due && !result.hidePrompt && result.snapshot.activeSeconds == 30, "a manual rest prompt stays up on the next tick")
}

do {
    let result = SessionEngine.tick(snapshot: base(at: t0, active: 10, paused: true), now: t0.addingTimeInterval(5), idleSeconds: 0, config: config)
    check(result.snapshot.activeSeconds == 10 && !result.becameDue, "pause freezes the counter")
}

do {
    let snoozed = base(at: t0, phase: .snoozed(until: t0.addingTimeInterval(5)), active: 100, paused: true)
    let result = SessionEngine.tick(snapshot: snoozed, now: t0.addingTimeInterval(5), idleSeconds: 0, config: config)
    check(result.snapshot.phase == .due && !result.becameDue, "a paused snooze becomes due without alerting")
}

do {
    let resting = base(at: t0, phase: .resting(until: t0.addingTimeInterval(5)), active: 100, paused: true)
    let result = SessionEngine.tick(snapshot: resting, now: t0.addingTimeInterval(5), idleSeconds: 0, config: config)
    check(result.hidePrompt && !result.breakFinished && result.snapshot.activeSeconds == 0, "a paused rest ends quietly")
}

do {
    let now = t0.addingTimeInterval(8)
    let started = SessionEngine.handle(.startBreak, snapshot: base(at: t0, phase: .due, active: 100), now: now, config: config)
    check(started.phase == .resting(until: now.addingTimeInterval(20)), "start break schedules the end")
    let snoozed = SessionEngine.handle(.snooze, snapshot: base(at: t0, phase: .due, active: 100), now: now, config: config)
    check(snoozed.phase == .snoozed(until: now.addingTimeInterval(15)), "snooze schedules the next prompt")
    let reset = SessionEngine.handle(.resetSession, snapshot: base(at: t0, phase: .due, active: 100), now: now, config: config)
    check(reset.phase == .working && reset.activeSeconds == 0, "reset clears the round")
    let until = t0.addingTimeInterval(50)
    let kept = SessionEngine.handle(.promptNow, snapshot: base(at: t0, phase: .resting(until: until), active: 80), now: now, config: config)
    check(kept.phase == .resting(until: until), "prompt now does not restart an active rest")
}

do {
    let future = RestSnapshot.restored(
        PersistedSession(activeSeconds: 80, phase: "resting", phaseUntilEpoch: t0.addingTimeInterval(30).timeIntervalSince1970, remindersPaused: false),
        now: t0
    )
    check(future.phase == .resting(until: t0.addingTimeInterval(30)), "restore keeps a future rest")
    let past = RestSnapshot.restored(
        PersistedSession(activeSeconds: 80, phase: "resting", phaseUntilEpoch: t0.addingTimeInterval(-5).timeIntervalSince1970, remindersPaused: false),
        now: t0
    )
    check(past.phase == .working && past.activeSeconds == 0, "restore completes an expired rest")
    let expiredSnooze = RestSnapshot.restored(
        PersistedSession(activeSeconds: 80, phase: "snoozed", phaseUntilEpoch: t0.addingTimeInterval(-1).timeIntervalSince1970, remindersPaused: false),
        now: t0
    )
    check(expiredSnooze.phase == .due && expiredSnooze.activeSeconds == 80, "restore turns an expired snooze into a prompt")
}

if failures == 0 {
    print("OK \(checks)")
} else {
    fputs("\(failures) failed / \(checks)\n", stderr)
    exit(1)
}
}
