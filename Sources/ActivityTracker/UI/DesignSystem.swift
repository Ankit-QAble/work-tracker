import SwiftUI

/// Shared visual language for the app: spacing/radius tokens, a card container,
/// and small reusable components — so the menu bar, dashboard, and settings all
/// read as one designed product instead of three separately-styled screens.
enum DS {
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8
    static let spacing: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let cardPadding: CGFloat = 16
}

/// A flat card surface that adapts to light/dark automatically via the system's
/// semantic control-background color, with a hairline border for definition
/// against the window background.
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
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
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

/// A compact KPI tile for the dashboard's summary row: icon, big value, label.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
