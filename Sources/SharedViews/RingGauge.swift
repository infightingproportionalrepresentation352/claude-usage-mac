import SwiftUI

/// The percentage ring. Same shape at every size — only `lineWidth` and the
/// font scale change between the menu bar popover and the three widget families.
struct RingGauge: View {
    let pct: Double?
    let level: Level
    var lineWidth: CGFloat = 8
    var showsPercent = true

    private var fraction: CGFloat {
        guard let pct else { return 0 }
        return CGFloat(min(max(pct / 100, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // Strokes straddle the path, so without this inset the outer half
                // spills past the frame and gets clipped by the container.
                Circle()
                    .stroke(level.tint.opacity(0.18), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                if pct != nil {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(level.tint,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(lineWidth / 2)
                }
                if showsPercent {
                    Text(Format.percent(pct))
                        // Scales with the ring so one view serves every widget family.
                        .font(.system(size: side * 0.28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pct == nil ? Level.none.tint : .primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A ring with its metric name and reset countdown underneath.
struct MetricGauge: View {
    let snapshot: Snapshot
    let metric: Metric
    var lineWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: 6) {
            RingGauge(pct: snapshot.pct(metric),
                      level: snapshot.level(metric),
                      lineWidth: lineWidth)
            VStack(spacing: 1) {
                Text(metric.label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(resets)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var resets: String {
        let text = Format.until(snapshot.resetsAt(metric))
        return text.isEmpty ? "—" : "resets \(text)"
    }
}

/// One "Today  1.2M  $3.40" line.
struct StatRow: View {
    let label: String
    let tokens: Int
    let cost: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(Format.tokens(tokens))
                .monospacedDigit()
            Text(Format.cost(cost))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                // Fixed width keeps the cost column aligned across rows.
                .frame(width: 52, alignment: .trailing)
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }
}

extension Snapshot {
    /// Placeholder for widget galleries and snapshot tests.
    static var preview: Snapshot {
        var stats = LogStats()
        stats.todayTokens = 1_240_000
        stats.todayCost = 3.40
        stats.weekTokens = 8_430_000
        stats.weekCost = 24.10
        stats.sessionTokens = 341_000
        stats.sessionCost = 1.02
        stats.projects = [
            ProjectUsage(name: "ai-job-hunter-assistant-app", tokens: 4_100_000, cost: 11.80),
            ProjectUsage(name: "claude-usage-streamdeck-plugin", tokens: 2_600_000, cost: 7.40),
            ProjectUsage(name: "tokensaver-streamdeck-plugin", tokens: 1_100_000, cost: 3.10),
            ProjectUsage(name: "dotfiles", tokens: 630_000, cost: 1.80),
        ]
        // Uneven, with idle days, so charts get reviewed against realistic shape
        // rather than a smooth ramp.
        let daily = [820, 0, 1_400, 2_050, 640, 0, 0, 1_180, 3_400, 2_900, 410, 1_760, 2_240, 1_240]
        let today = Calendar.current.startOfDay(for: Date())
        stats.days = daily.enumerated().compactMap { offset, thousands in
            guard let day = Calendar.current.date(
                byAdding: .day, value: offset - (daily.count - 1), to: today) else { return nil }
            return DayUsage(day: day, tokens: thousands * 1_000,
                            cost: Double(thousands) * 0.0029)
        }
        return Snapshot(
            usage: UsageData(
                fiveHour: UsageNode(utilization: 42,
                                    resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60)),
                sevenDay: UsageNode(utilization: 18,
                                    resetsAt: Date().addingTimeInterval(4 * 86400 + 6 * 3600))),
            stats: stats)
    }
}
