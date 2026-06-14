import Foundation

/// Decides whether a timestamp falls within a period, relative to `now`.
///
/// Default bucketing is the user's **local** calendar day (a "today" should mean
/// the user's day); a `.utc` zone is available for parity with tools that bucket
/// by UTC date string. Week start respects the locale's `firstWeekday`.
public struct PeriodBucketer: Sendable {
    public enum Zone: String, Sendable, Codable, CaseIterable { case local, utc }

    public let now: Date
    private let calendar: Calendar

    public init(zone: Zone = .local, now: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone == .utc ? TimeZone(identifier: "UTC")! : TimeZone.current
        cal.firstWeekday = Calendar.current.firstWeekday
        self.calendar = cal
        self.now = now
    }

    public func contains(_ date: Date, in period: Period) -> Bool {
        switch period {
        case .today: calendar.isDate(date, inSameDayAs: now)
        case .thisWeek: calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth: calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .rolling7: date > now.addingTimeInterval(-7 * 86_400) && date <= now
        case .rolling30: date > now.addingTimeInterval(-30 * 86_400) && date <= now
        }
    }
}
