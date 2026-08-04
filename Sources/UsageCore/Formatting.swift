import Foundation

/// Severity band for a utilization percentage. Lives here rather than in the
/// views so both the menu bar and the widget colour identically, and so
/// UsageCore stays free of SwiftUI.
public enum Level: String, Sendable {
    case none    // no data
    case ok
    case warn
    case critical

    public static func of(_ pct: Double?, warn: Double = 50, critical: Double = 80) -> Level {
        guard let pct else { return .none }
        if pct >= critical { return .critical }
        if pct >= warn { return .warn }
        return .ok
    }
}

public enum Format {

    /// "4d 6h" / "2h 14m" / "45m" / "" when unknown. Clamps at zero rather than
    /// counting up past a reset we haven't refreshed through yet.
    public static func until(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        var seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86400
        seconds -= days * 86400
        let hours = seconds / 3600
        seconds -= hours * 3600
        let minutes = seconds / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1e9...:  return trim(v / 1e9, wide: v >= 1e10) + "B"
        case 1e6...:  return trim(v / 1e6, wide: v >= 1e7) + "M"
        case 1e3...:  return trim(v / 1e3, wide: v >= 1e4) + "K"
        default:      return "\(n)"
        }
    }

    public static func cost(_ usd: Double) -> String {
        if usd >= 1000 { return "$" + trim(usd / 1000, wide: false) + "k" }
        if usd >= 100 { return "$" + String(format: "%.0f", usd) }
        return "$" + String(format: "%.2f", usd)
    }

    public static func percent(_ pct: Double?) -> String {
        guard let pct else { return "--" }
        return "\(Int(pct.rounded()))%"
    }

    /// One decimal place until the integer part hits three digits, then none —
    /// keeps the string at four characters or fewer for narrow key faces.
    private static func trim(_ v: Double, wide: Bool) -> String {
        String(format: wide ? "%.0f" : "%.1f", v)
    }
}
