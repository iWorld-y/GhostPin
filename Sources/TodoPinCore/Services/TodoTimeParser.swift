import Foundation

public struct ParsedReminderTime: Equatable, Sendable {
    public let date: Date
    public let matchedText: String

    public init(date: Date, matchedText: String) {
        self.date = date
        self.matchedText = matchedText
    }
}

public struct TodoTimeParser: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ text: String, now: Date = Date()) -> ParsedReminderTime? {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "號", with: "号")

        guard let timeMatch = firstTimeMatch(in: normalized) else {
            return nil
        }

        let day = resolvedDay(in: normalized, before: timeMatch.range.lowerBound, now: now)
        guard let date = makeDate(day: day.date, hour: timeMatch.hour, minute: timeMatch.minute) else {
            return nil
        }

        let resolvedDate = timeMatch.hasExplicitDay || day.hasExplicitDay || date > now
            ? date
            : calendar.date(byAdding: .day, value: 1, to: date) ?? date

        let matchedLowerBound = day.range?.lowerBound ?? timeMatch.range.lowerBound
        let matchedText = String(normalized[matchedLowerBound..<timeMatch.range.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedReminderTime(date: resolvedDate, matchedText: matchedText)
    }

    private func firstTimeMatch(in text: String) -> TimeMatch? {
        let nsText = text as NSString
        let pattern = #"(?:(上午|早上|中午|下午|晚上|今晚|明早)\s*)?(\d{1,2})(?:\s*(?:点|點)\s*(半|一刻|三刻|\d{1,2})?\s*分?|:(\d{1,2}))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              let hourRange = Range(match.range(at: 2), in: text),
              let baseHour = Int(text[hourRange]) else {
            return nil
        }

        var hour = baseHour
        var minute = 0
        if let colonMinute = string(at: 4, in: match, text: text),
           let parsedMinute = Int(colonMinute) {
            minute = parsedMinute
        } else if let minuteText = string(at: 3, in: match, text: text) {
            switch minuteText {
            case "半":
                minute = 30
            case "一刻":
                minute = 15
            case "三刻":
                minute = 45
            default:
                minute = Int(minuteText) ?? 0
            }
        }

        guard (0...23).contains(hour), (0...59).contains(minute),
              let range = Range(match.range, in: text) else {
            return nil
        }

        let period = string(at: 1, in: match, text: text)
        if let period {
            if ["下午", "晚上", "今晚"].contains(period), hour < 12 {
                hour += 12
            } else if period == "中午", hour < 11 {
                hour += 12
            } else if period == "明早", hour == 12 {
                hour = 0
            }
        }

        return TimeMatch(
            range: range,
            hour: hour,
            minute: minute,
            hasExplicitDay: period == "今晚" || period == "明早"
        )
    }

    private func resolvedDay(in text: String, before timeIndex: String.Index, now: Date) -> DayMatch {
        let prefix = String(text[..<timeIndex])
        if let absolute = absoluteDay(in: prefix, now: now) {
            return absolute
        }

        let todayStart = calendar.startOfDay(for: now)
        let relativeRules: [(String, Int)] = [
            ("明早", 1),
            ("明天", 1),
            ("后天", 2),
            ("後天", 2),
            ("今天", 0),
            ("今晚", 0)
        ]

        for (keyword, offset) in relativeRules {
            if let range = text.range(of: keyword) {
                let date = calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
                return DayMatch(date: date, range: range, hasExplicitDay: true)
            }
        }

        return DayMatch(date: todayStart, range: nil, hasExplicitDay: false)
    }

    private func absoluteDay(in prefix: String, now: Date) -> DayMatch? {
        let currentYear = calendar.component(.year, from: now)
        let patterns = [
            #"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})(?:日|号)?"#,
            #"(\d{1,2})月(\d{1,2})(?:日|号)?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let nsPrefix = prefix as NSString
            guard let match = regex.matches(in: prefix, range: NSRange(location: 0, length: nsPrefix.length)).last else {
                continue
            }

            let year: Int
            let month: Int
            let day: Int
            if match.numberOfRanges == 4 {
                guard let yearText = string(at: 1, in: match, text: prefix),
                      let monthText = string(at: 2, in: match, text: prefix),
                      let dayText = string(at: 3, in: match, text: prefix),
                      let parsedYear = Int(yearText),
                      let parsedMonth = Int(monthText),
                      let parsedDay = Int(dayText) else {
                    continue
                }
                year = parsedYear
                month = parsedMonth
                day = parsedDay
            } else {
                guard let monthText = string(at: 1, in: match, text: prefix),
                      let dayText = string(at: 2, in: match, text: prefix),
                      let parsedMonth = Int(monthText),
                      let parsedDay = Int(dayText) else {
                    continue
                }
                year = currentYear
                month = parsedMonth
                day = parsedDay
            }

            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                continue
            }
            return DayMatch(date: date, range: nil, hasExplicitDay: true)
        }

        return nil
    }

    private func makeDate(day: Date, hour: Int, minute: Int) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func string(at index: Int, in match: NSTextCheckingResult, text: String) -> String? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

private struct TimeMatch {
    let range: Range<String.Index>
    let hour: Int
    let minute: Int
    let hasExplicitDay: Bool
}

private struct DayMatch {
    let date: Date
    let range: Range<String.Index>?
    let hasExplicitDay: Bool
}
