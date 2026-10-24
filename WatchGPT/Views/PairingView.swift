import SwiftUI

/// Connect your ChatGPT account: scan the QR with the iPhone, sign in, type the code.
struct PairingView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                switch auth.phase {
                case .signedOut, .requestingCode, .signedIn:
                    ProgressView()
                        .padding(.top, 30)
                    Text("Готовлю код входа…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case let .waiting(code):
                    WaitingForApproval(code: code)

                case let .failed(message):
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
            }
            .frame(maxWidth: .infinity)
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
        VStack(spacing: 8) {
            QRCodeView(text: code.verificationURL.absoluteString)
                .frame(width: 128, height: 128)

            Text("Отсканируйте камерой iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(formatted(code.userCode))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 4)

            Text("Войдите в ChatGPT и введите этот код")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Жду подтверждения · \(left / 60):\(String(format: "%02d", left % 60))")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Или откройте вручную:")
                Text(code.verificationURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .foregroundStyle(Theme.accent)
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)

            Button("Новый код") { auth.startPairing() }
                .font(.footnote)
                .padding(.top, 4)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("QR-код для входа")
    }
}
