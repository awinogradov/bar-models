import Foundation
import UsageCore

/// Entry point. Normally launches the SwiftUI menu-bar app; with `--scan-once`
/// it runs a single synchronous scan, prints the totals, and exits — a headless
/// smoke test against the real `~/.claude` tree (no GUI, returns to the shell).
@main
struct Main {
    static func main() {
        if CommandLine.arguments.contains("--scan-once") {
            runScanOnce()
            return
        }
        InlineUsageApp.main()
    }

    private static func runScanOnce() {
        let started = Date()
        let events = UsageScanner().scan()
        let snapshot = Aggregator().aggregate(events, using: PeriodBucketer(now: Date()))
        let elapsed = Date().timeIntervalSince(started)

        print("inline-usage --scan-once")
        print("scanned \(snapshot.eventCount) deduped events in \(String(format: "%.2fs", elapsed))\n")
        for period in Period.allCases {
            let t = snapshot.tokens(period)
            print(String(format: "%-12@  in+out %@   billable %@",
                         period.label as NSString,
                         UsageFormat.grouped(t.inputOutput) as NSString,
                         UsageFormat.grouped(t.billableTotal) as NSString))
        }
        let m = snapshot.tokens(.thisMonth)
        print("\nthis month — in \(UsageFormat.grouped(m.input)) · out \(UsageFormat.grouped(m.output)) · cache-write \(UsageFormat.grouped(m.cacheWrite)) · cache-read \(UsageFormat.grouped(m.cacheRead))")
    }
}
