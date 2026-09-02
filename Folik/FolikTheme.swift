import SwiftUI
import UIKit

enum FolikTheme {
    static let cobalt = Color(red: 0.20, green: 0.42, blue: 0.89)
    static let cobaltPressed = Color(red: 0.15, green: 0.34, blue: 0.76)
    static let ink = Color(uiColor: .label)
    static let mutedInk = Color(uiColor: .secondaryLabel)
    static let surface = Color(uiColor: .systemBackground)
    static let raisedSurface = Color(uiColor: .secondarySystemBackground)
    static let recessedSurface = Color(uiColor: .tertiarySystemBackground)
    static let separator = Color(uiColor: .separator)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.071, blue: 0.094, alpha: 1)
            : UIColor(red: 0.82, green: 0.85, blue: 0.89, alpha: 1)
    })

    static let readerCanvasUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.071, blue: 0.094, alpha: 1)
            : UIColor(red: 0.82, green: 0.85, blue: 0.89, alpha: 1)
    }

    static let annotationYellow = UIColor(red: 1, green: 0.79, blue: 0.20, alpha: 0.56)
    static let annotationBlue = UIColor(red: 0.20, green: 0.42, blue: 0.89, alpha: 0.90)
    static let annotationRed = UIColor(red: 0.86, green: 0.25, blue: 0.24, alpha: 0.88)
}

struct FolikWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            FolikMark(size: compact ? 32 : 40)

            Text("FOLIK")
                .font(compact ? .headline : .title2.weight(.bold))
                .tracking(1.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folik")
    }
}

private struct FolikMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(FolikTheme.cobalt)
            Image(systemName: "doc.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
            Text("F")
                .font(.system(size: size * 0.21, weight: .black, design: .rounded))
                .foregroundStyle(FolikTheme.cobalt)
                .offset(x: -size * 0.025, y: size * 0.055)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
