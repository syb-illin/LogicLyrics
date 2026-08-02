import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.36, green: 0.53, blue: 0.78)
    static let cyan = Color(red: 0.32, green: 0.62, blue: 0.70)
    static let coral = Color(red: 0.76, green: 0.43, blue: 0.48)
    static let green = Color(red: 0.34, green: 0.64, blue: 0.49)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.052, green: 0.055, blue: 0.065),
            Color(red: 0.066, green: 0.069, blue: 0.080)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct AppPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 14
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    Color(red: 0.085, green: 0.087, blue: 0.10)
                } else {
                    Color.white.opacity(0.035)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.065), lineWidth: 1)
            }
    }
}

extension View {
    func appPanel(radius: CGFloat = 18, padding: CGFloat = 18) -> some View {
        modifier(AppPanel(radius: radius, padding: padding))
    }
}

struct AccentIcon: View {
    let systemName: String
    var color = AppTheme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .stroke(color.opacity(0.16), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct CapsuleStatus: View {
    let text: String
    let systemName: String
    var color = AppTheme.green

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.055), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

struct ProcessingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let state: OperationState
    var cancel: (() -> Void)?

    var body: some View {
        if case .running(let message, let startedAt) = state {
            ZStack {
                Color.black.opacity(0.48).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppTheme.accent)
                        .accessibilityLabel(L10n.text("Operation in progress"))
                    Text(message).font(.headline).multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let cancel {
                        Button(L10n.text("Cancel"), role: .cancel, action: cancel).buttonStyle(.bordered)
                    }
                }
                .padding(26)
                .frame(minWidth: 280)
                .background {
                    if reduceTransparency {
                        Color(red: 0.085, green: 0.087, blue: 0.10)
                    } else {
                        Rectangle().fill(.regularMaterial)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12)) }
                .shadow(color: .black.opacity(0.35), radius: 30, y: 15)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("Operation in progress"))
            .transition(reduceMotion ? .identity : .opacity)
            .zIndex(100)
        }
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return seconds < 60
            ? L10n.format("%d s", seconds)
            : L10n.format("%d min %02d s", seconds / 60, seconds % 60)
    }
}
