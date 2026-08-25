import Foundation

extension Calendar {
    public func ghostPinDayStart(for date: Date) -> Date {
        startOfDay(for: date)
    }

    public func ghostPinDayEnd(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    public func ghostPinPreviousDayStart(before date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: -1, to: start) ?? start
    }
}
