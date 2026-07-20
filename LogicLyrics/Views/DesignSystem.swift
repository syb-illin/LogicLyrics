import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.46, green: 0.36, blue: 0.96)
    static let cyan = Color(red: 0.18, green: 0.72, blue: 0.88)
    static let coral = Color(red: 0.97, green: 0.42, blue: 0.50)
    static let green = Color(red: 0.24, green: 0.76, blue: 0.58)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.06, blue: 0.09),
            Color(red: 0.085, green: 0.075, blue: 0.14),
            Color(red: 0.045, green: 0.07, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppPanel: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
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
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
            .shadow(color: color.opacity(0.32), radius: 10, y: 5)
    }
}

struct CapsuleStatus: View {
    let text: String
    let systemName: String
    var color = AppTheme.green

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
    }
}

struct ProcessingOverlay: View {
    let state: OperationState
    var cancel: (() -> Void)?

    var body: some View {
        if case .running(let message, let startedAt) = state {
            ZStack {
                Color.black.opacity(0.48).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(AppTheme.cyan)
                    Text(message).font(.headline).multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let cancel {
                        Button("Annuler", role: .cancel, action: cancel).buttonStyle(.bordered)
                    }
                }
                .padding(26)
                .frame(minWidth: 280)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12)) }
                .shadow(color: .black.opacity(0.35), radius: 30, y: 15)
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) s" : String(format: "%d min %02d s", seconds / 60, seconds % 60)
    }
}
