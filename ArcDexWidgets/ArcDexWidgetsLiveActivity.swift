import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Shiny counter on the Lock Screen and in the Dynamic Island.
struct HuntLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HuntActivityAttributes.self) { context in
            LockScreenHuntView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        HuntSprite(data: context.attributes.spriteData, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.pokemonName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(context.state.odds)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(context.state.count)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: Double(context.state.count)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(context.attributes.unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HuntTimerText(state: context.state)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(context.state.chanceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(intent: HuntCountIntent(huntID: context.attributes.huntID, amount: -1)) {
                            Image(systemName: "minus")
                                .font(.headline.weight(.bold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .background(.white.opacity(0.15), in: Circle())
                        Button(intent: HuntCountIntent(huntID: context.attributes.huntID, amount: context.attributes.step)) {
                            Text("+\(context.attributes.step)")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 92, height: 44)
                        }
                        .buttonStyle(.plain)
                        .background(gradient(context.attributes), in: Capsule())
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
            } compactLeading: {
                HuntSprite(data: context.attributes.spriteData, size: 24)
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color(rgb: context.attributes.colorA))
                    .contentTransition(.numericText(value: Double(context.state.count)))
            } minimal: {
                Text(minimalCount(context.state.count))
                    .font(.caption2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color(rgb: context.attributes.colorA))
            }
            .keylineTint(Color(rgb: context.attributes.colorA))
        }
    }
}

struct LockScreenHuntView: View {
    let context: ActivityViewContext<HuntActivityAttributes>

    var body: some View {
        let a = context.attributes
        let s = context.state
        HStack(spacing: 12) {
            HuntSprite(data: a.spriteData, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(a.pokemonName).font(.headline).lineLimit(1)
                    Image(systemName: "sparkles").font(.caption.weight(.bold)).foregroundStyle(.yellow)
                }
                Text("\(a.gameTitle) · \(s.odds)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HuntTimerText(state: s)
                    Text("· " + s.chanceText)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(s.count)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(s.count)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(a.unit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            VStack(spacing: 6) {
                Button(intent: HuntCountIntent(huntID: a.huntID, amount: a.step)) {
                    Text("+\(a.step)")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 44)
                }
                .buttonStyle(.plain)
                .background(gradient(a), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button(intent: HuntCountIntent(huntID: a.huntID, amount: -1)) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 22)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.15), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

struct HuntSprite: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: size, height: size)
        }
    }
}

struct HuntTimerText: View {
    let state: HuntActivityAttributes.ContentState

    var body: some View {
        if let start = state.timerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(Duration.seconds(state.elapsed).formatted(.time(pattern: state.elapsed >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        }
    }
}

private func gradient(_ a: HuntActivityAttributes) -> LinearGradient {
    LinearGradient(colors: [Color(rgb: a.colorA), Color(rgb: a.colorB)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private func minimalCount(_ n: Int) -> String {
    n >= 10_000 ? "\(n / 1000)k" : "\(n)"
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
