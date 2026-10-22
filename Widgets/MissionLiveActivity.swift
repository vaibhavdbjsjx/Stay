import ActivityKit
import SwiftUI
import WidgetKit

struct MissionLiveActivity: Widget {
    private static let cream = Color(hex: 0xFBF3E6)
    private static let apricot = Color(hex: 0xF2A477)
    private static let calm = Color(hex: 0x84C79F)
    private static let alert = Color(hex: 0xF08A76)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MissionActivityAttributes.self) { context in
            LockScreenMissionView(context: context)
                .activityBackgroundTint(Color(hex: 0x24443B))
                .activitySystemActionForegroundColor(Self.cream)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        StayMark(faceColor: .black).frame(width: 26, height: 26)
                        Text(context.attributes.dogName).font(.headline).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(tint(context.state.status))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if context.attributes.targetSeconds < 1800 || context.state.status != .calm {
                            ProgressView(timerInterval: context.attributes.startedAt...max(context.attributes.targetEnd, context.attributes.startedAt.addingTimeInterval(1)), countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(tint(context.state.status))
                        }
                        Text(statusText(context)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status == .alert ? "exclamationmark.triangle.fill" : "pawprint.fill")
                    .foregroundStyle(tint(context.state.status))
            } compactTrailing: {
                timer(context).monospacedDigit().frame(maxWidth: 52).foregroundStyle(tint(context.state.status))
            } minimal: {
                Image(systemName: context.state.status == .alert ? "exclamationmark.triangle.fill" : "pawprint.fill")
                    .foregroundStyle(tint(context.state.status))
            }
            .keylineTint(tint(context.state.status))
        }
    }

    private func timer(_ context: ActivityViewContext<MissionActivityAttributes>) -> Text {
        if let ended = context.state.endedAt {
            return Text(DurationText.clock(ended.timeIntervalSince(context.attributes.startedAt)))
        }
        return Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
    }

    private func tint(_ status: MissionActivityAttributes.ContentState.Status) -> Color {
        switch status {
        case .calm: Self.calm
        case .alert: Self.alert
        case .timeToReturn: Self.apricot
        case .ended: Self.cream
        }
    }

    private func statusText(_ context: ActivityViewContext<MissionActivityAttributes>) -> String {
        switch context.state.status {
        case .calm: String(localized: "All calm · target \(DurationText.short(context.attributes.targetSeconds))")
        case .alert: String(localized: "\(context.state.lastEventLabel ?? String(localized: "Stress")) detected · open Stay")
        case .timeToReturn: String(localized: "Time to head back")
        case .ended: String(localized: "Mission ended")
        }
    }

    fileprivate static func statusColor(_ status: MissionActivityAttributes.ContentState.Status) -> Color {
        switch status {
        case .calm: calm
        case .alert: alert
        case .timeToReturn: apricot
        case .ended: cream
        }
    }
}

private struct LockScreenMissionView: View {
    var context: ActivityViewContext<MissionActivityAttributes>
    private let cream = Color(hex: 0xFBF3E6)

    var body: some View {
        HStack(spacing: 14) {
            StayMark(faceColor: Color(hex: 0x24443B)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.endedAt == nil ? String(localized: "\(context.attributes.dogName) is home alone") : String(localized: "Mission ended"))
                    .font(.headline)
                    .foregroundStyle(cream)
                Text(detail).font(.caption).foregroundStyle(cream.opacity(0.75))
                if context.state.endedAt == nil {
                    ProgressView(timerInterval: context.attributes.startedAt...max(context.attributes.targetEnd, context.attributes.startedAt.addingTimeInterval(1)), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(MissionLiveActivity.statusColor(context.state.status))
                }
            }
            Spacer()
            Group {
                if let ended = context.state.endedAt {
                    Text(DurationText.clock(ended.timeIntervalSince(context.attributes.startedAt)))
                } else {
                    Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                }
            }
            .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
            .foregroundStyle(MissionLiveActivity.statusColor(context.state.status))
            .frame(maxWidth: 110, alignment: .trailing)
        }
        .padding(16)
    }

    private var detail: String {
        switch context.state.status {
        case .calm: String(localized: "All calm · target \(DurationText.short(context.attributes.targetSeconds))")
        case .alert: String(localized: "\(context.state.eventCount) alert(s) · \(context.state.lastEventLabel ?? "")")
        case .timeToReturn: String(localized: "Time to head back calmly")
        case .ended: String(localized: "\(context.state.eventCount) alert(s)")
        }
    }
}
