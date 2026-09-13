import SwiftUI

/// Shared visual language for the app: spacing/radius tokens, a card container,
/// and small reusable components — so the menu bar, dashboard, and settings all
/// read as one designed product instead of three separately-styled screens.
enum DS {
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 8
    static let spacing: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let cardPadding: CGFloat = 16
}

/// A lifted card surface that adapts to light/dark automatically via the
/// system's semantic control-background color, with a hairline border plus a
/// soft shadow for a bit of depth against the window background — flat cards
/// with just a border read as noticeably flatter/older than this.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// A section title used above a card or group of cards — small caps, muted,
/// consistent across the dashboard and settings.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

/// A compact KPI tile for the dashboard's summary row: a tinted icon badge,
/// a big value, and a label underneath.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A quiet, icon-only circular button — chevrons, refresh — filled on hover so
/// it reads as interactive without competing with the primary actions next to
/// it. SwiftUI's stock `.bordered` style looks noticeably plainer for this.
struct SubtleIconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(
                    configuration.isPressed
                        ? Color.primary.opacity(0.14)
                        : (isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05))
                )
            )
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A pill-shaped button with a tinted fill — used for secondary header actions
/// ("Today"). Filled but muted, so it sits between the quiet icon buttons and
/// the accent-colored primary action.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.16 : 0.1))
            )
            .foregroundStyle(tint)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A solid, accent-colored pill for the one primary action in a toolbar —
/// Export, here — so it reads as the thing you're most likely to want.
struct ProminentPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.accentColor.opacity(0.35), radius: configuration.isPressed ? 2 : 6, y: 2)
    }
}
