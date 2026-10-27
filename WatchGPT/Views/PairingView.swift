import SwiftUI

/// Connect your ChatGPT account: scan the QR with the iPhone, sign in, type the code.
struct PairingView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.phase {
            case .signedOut, .requestingCode, .signedIn:
                VStack(spacing: 8) {
                    Spinner(size: 30, lineWidth: 3)
                    Text("Готовлю код входа…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .waiting(code):
                ScrollView {
                    WaitingForApproval(code: code)
                        .frame(maxWidth: .infinity)
                }
                .id(code.deviceAuthID)

            case let .failed(message):
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                        Text(message)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                        Button("Попробовать снова") { auth.startPairing() }
                            .tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
                .id(message)
            }
        }
        .navigationTitle("WatchGPT")
        .onAppear {
            if auth.phase == .signedOut { auth.startPairing() }
        }
    }
}

private struct WaitingForApproval: View {
    @Environment(AuthService.self) private var auth
    let code: OAuth.DeviceCode

    var body: some View {
        VStack(spacing: 0) {
            QRCodeView(text: code.verificationURL.absoluteString)
                .frame(width: 104, height: 104)

            Text(formatted(code.userCode))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .tracking(1)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 9)

            Text("Сканируйте iPhone и введите код")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
                HStack(spacing: 5) {
                    Spinner(size: 10, lineWidth: 1.5)
                    Text("Жду входа · \(left / 60):\(String(format: "%02d", left % 60))")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 6)

            VStack(spacing: 2) {
                Text("Или откройте вручную")
                    .foregroundStyle(Theme.secondaryText)
                Text(code.verificationURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }
            .font(.caption2)
            .padding(.top, 18)

            Button {
                auth.startPairing()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Новый код")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .glassBackground(Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    private func formatted(_ code: String) -> String {
        guard !code.contains("-"), code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        let qr = QRCode.encode(text, ecc: .medium)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            guard let qr else { return }
            let quiet = 3
            let count = qr.size + quiet * 2
            let cell = min(size.width, size.height) / CGFloat(count)
            var path = Path()
            for y in 0..<qr.size {
                for x in 0..<qr.size where qr.isDark(x: x, y: y) {
                    path.addRect(CGRect(
                        x: CGFloat(x + quiet) * cell,
                        y: CGFloat(y + quiet) * cell,
                        width: cell + 0.25,
                        height: cell + 0.25
                    ))
                }
            }
            context.fill(path, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("QR-код для входа")
    }
}
