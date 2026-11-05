import SwiftUI

struct HistoryErrorView: View {
    let message: String
    var compact = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            if !compact {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text(message)
                .font(compact ? .caption2 : .footnote)
                .foregroundStyle(compact ? .orange : .white)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Повторить")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassBackground(Capsule(), interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, compact ? 2 : 10)
        .frame(maxWidth: .infinity)
    }
}
