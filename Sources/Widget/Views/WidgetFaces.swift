import SwiftUI

/// Deliberately not `WidgetFamily`: keeping WidgetKit out of these views lets the
/// snapshot tests render them without linking an app extension.
enum Face: String, CaseIterable {
    case small, medium, large

    /// Points, at 1x. WidgetKit's macOS system family sizes.
    var size: CGSize {
        switch self {
        case .small:  return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large:  return CGSize(width: 364, height: 382)
        }
    }
}

/// The widget body for every family. Split out from the `@main` entry point so
/// the snapshot tests can render these without linking an app extension.
struct UsageWidgetView: View {
    let snapshot: Snapshot?
    let face: Face

    var body: some View {
        Group {
            if let snapshot {
                switch face {
                case .small:  small(snapshot)
                case .medium: medium(snapshot)
                case .large:  large(snapshot)
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Families

    private func small(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 8) {
            RingGauge(pct: snapshot.sessionPct,
                      level: snapshot.level(.session),
                      lineWidth: 11)
            VStack(spacing: 2) {
                Text(Metric.session.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(resets(snapshot, .session))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            staleMark(snapshot)
        }
    }

    private func medium(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 20) {
            MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 10)
            MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 10)
            VStack(alignment: .leading, spacing: 7) {
                stat("TODAY", snapshot.stats.todayTokens, snapshot.stats.todayCost)
                stat("WEEK", snapshot.stats.weekTokens, snapshot.stats.weekCost)
                staleMark(snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func large(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 26) {
                MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 12)
                MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 12)
            }
            .frame(maxHeight: 150)

            VStack(spacing: 9) {
                StatRow(label: "Today", tokens: snapshot.stats.todayTokens,
                        cost: snapshot.stats.todayCost)
                Divider()
                StatRow(label: "This week", tokens: snapshot.stats.weekTokens,
                        cost: snapshot.stats.weekCost)
                Divider()
                StatRow(label: "Session", tokens: snapshot.stats.sessionTokens,
                        cost: snapshot.stats.sessionCost)
            }
            staleMark(snapshot)
        }
    }

    // MARK: - Pieces

    private func stat(_ label: String, _ tokens: Int, _ cost: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(Format.tokens(tokens))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(Format.cost(cost))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func resets(_ snapshot: Snapshot, _ metric: Metric) -> String {
        let text = Format.until(snapshot.resetsAt(metric))
        return text.isEmpty ? "—" : "resets \(text)"
    }

    /// The widget can't fix a failed refresh itself — the host app owns that — so
    /// this says the numbers are old rather than offering an action.
    @ViewBuilder
    private func staleMark(_ snapshot: Snapshot) -> some View {
        if snapshot.error != nil {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(snapshot.stale ? "outdated" : "no update")
            }
            .font(.system(size: 9))
            .foregroundStyle(Level.warn.tint)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Open Claude Usage")
                .font(.system(size: 11, weight: .medium))
            Text("The menu bar app supplies the data")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}
