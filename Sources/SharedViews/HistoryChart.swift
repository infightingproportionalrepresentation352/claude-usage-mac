import SwiftUI

/// Daily tokens as bars. Deliberately not Swift Charts — at this size the axes,
/// legends and gesture handling it brings are all things we'd have to turn off.
struct HistoryChart: View {
    let days: [DayUsage]
    var height: CGFloat = 34
    var tint: Color = Level.ok.tint

    private var peak: Int {
        max(days.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 1.5)
                        // Idle days keep a visible stub so the run of dates stays
                        // readable instead of turning into gaps.
                        .fill(tint.opacity(day.tokens == 0 ? 0.15 : 0.85))
                        .frame(height: max(2, height * CGFloat(day.tokens) / CGFloat(peak)))
                }
            }
            .frame(height: height, alignment: .bottom)

            if let first = days.first?.day, let last = days.last?.day {
                HStack {
                    Text(Self.short.string(from: first))
                    Spacer()
                    Text(Self.short.string(from: last))
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()
}

/// Busiest projects, as a compact bar-backed list.
struct ProjectList: View {
    let projects: [ProjectUsage]
    var limit = 3

    private var shown: [ProjectUsage] { Array(projects.prefix(limit)) }
    private var peak: Int { max(shown.first?.tokens ?? 0, 1) }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(shown) { project in
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Level.ok.tint.opacity(0.16))
                                .frame(width: geo.size.width * CGFloat(project.tokens) / CGFloat(peak))
                        }
                        Text(project.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 4)
                    }
                    .frame(height: 16)

                    Text(Format.tokens(project.tokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10))
            }
            if projects.isEmpty {
                Text("No activity this week")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A small section heading, so the popover reads as grouped rather than a wall.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
