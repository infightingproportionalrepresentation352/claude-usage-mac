import SwiftUI

struct MenuView: View {
    let snapshot: Snapshot?
    let isRefreshing: Bool
    var refresh: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                gauges(snapshot)
                Divider().padding(.vertical, 10)
                stats(snapshot)
                if let message = snapshot.errorMessage {
                    Divider().padding(.vertical, 10)
                    banner(message, stale: snapshot.stale)
                }
                Divider().padding(.vertical, 10)
                footer(snapshot)
            } else {
                loading
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func gauges(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 18) {
            MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 9)
            MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 9)
        }
        .frame(height: 118)
    }

    private func stats(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 5) {
            StatRow(label: "Today", tokens: snapshot.stats.todayTokens,
                    cost: snapshot.stats.todayCost)
            StatRow(label: "This week", tokens: snapshot.stats.weekTokens,
                    cost: snapshot.stats.weekCost)
            StatRow(label: "Session", tokens: snapshot.stats.sessionTokens,
                    cost: snapshot.stats.sessionCost)
            if !snapshot.stats.ok {
                Text("~/.claude/projects not readable")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func banner(_ message: String, stale: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Level.warn.tint)
            Text(stale ? "\(message) — showing older numbers" : message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10))
    }

    // ponytail: text buttons, not an icon row — it's what menu bar apps
    // conventionally do, and it reads without a tooltip.
    private func footer(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Clamped: a snapshot stamped microseconds ago otherwise reads as
            // "in 0 sec.", which looks like a bug.
            Text("Updated \(Self.relative.localizedString(for: min(snapshot.updatedAt, Date()), relativeTo: Date()))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 14) {
                Button("Refresh", action: refresh)
                    .disabled(isRefreshing)
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            // The first transcript scan reads everything in the 7-day window,
            // which is gigabytes on an active machine.
            Text("Reading usage…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
