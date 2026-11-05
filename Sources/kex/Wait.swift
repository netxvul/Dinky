import Foundation

/// Polls every 10 ms until the condition holds or the time is up. True if it held.
func waitUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(10_000)
    }
    return condition()
}
