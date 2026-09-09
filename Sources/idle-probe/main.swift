import Foundation
import PresenceCore

// Experiment: does the power assertion reset HIDIdleTime?
//
// Waits for the machine to actually go idle for 60s — instead of relying on
// the operator staying still during an agreed-upon window, which is what
// contaminated the manual measurement taken during design.

let reader = IdleReader()
let declarer = ActivityDeclarer()

let threshold: TimeInterval = 60
let deadline = Date().addingTimeInterval(3600)

print("waiting for \(Int(threshold))s of real idleness (up to 1h)...")

while Date() < deadline {
    guard reader.idleSeconds() >= threshold else {
        Thread.sleep(forTimeInterval: 5)
        continue
    }

    let before = reader.idleSeconds()
    do {
        try declarer.declare()
    } catch {
        print("FAILED to declare activity: \(error)")
        exit(1)
    }
    Thread.sleep(forTimeInterval: 1)
    let after = reader.idleSeconds()

    print(String(format: "idle ANTES = %.1fs | DEPOIS = %.1fs", before, after))

    if after < 5 {
        print("RESULT: the assertion DOES reset the counter. .declared mode is viable.")
    } else if after >= before {
        print("RESULT: the assertion does NOT reset the counter. The app will live in .synthetic.")
    } else {
        print("RESULT: inconclusive (partial drop). Re-run the probe.")
    }
    exit(0)
}

print("giving up: the machine did not go idle for \(Int(threshold))s within 1 hour")
exit(2)
