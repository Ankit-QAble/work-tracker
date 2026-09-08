import SwiftUI
import AppKit

struct ScreenshotStripView: View {
    let screenshots: [Screenshot]

    var body: some View {
        if screenshots.isEmpty {
            Text("No screenshots for this day.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(screenshots) { shot in
                        ScreenshotThumbnail(shot: shot)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ScreenshotThumbnail: View {
    let shot: Screenshot
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            ThumbnailImage(path: shot.filePath)
                .frame(width: 160, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 6, y: 3)
                .scaleEffect(isHovering ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }

            VStack(spacing: 1) {
                Text(shot.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                if let score = shot.activityScore {
                    Text("activity \(score)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ThumbnailImage: View {
    let path: String

    var body: some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(Color.gray.opacity(0.15))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
