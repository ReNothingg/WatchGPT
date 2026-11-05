import SwiftUI

struct HistoryBubble: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    var images: [RemoteImage] = []
    var conversationID: String

    private var text: String {
        images.isEmpty ? message.text : HistoryText.withoutImageLabel(message.text)
    }

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                if !images.isEmpty {
                    HStack {
                        Spacer(minLength: images.count == 1 ? 36 : 20)
                        gallery
                    }
                }
                if !text.isEmpty {
                    HStack {
                        Spacer(minLength: 28)
                        MarkdownText(text: text, style: .footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: Theme.bubble)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !images.isEmpty { gallery }
                if !text.isEmpty {
                    MarkdownText(text: text, scale: store.answerFontScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { store.speaker.toggle(text) }
                }
            }
        }
    }

    @ViewBuilder private var gallery: some View {
        if images.count == 1 {
            RemoteImageView(image: images[0], conversationID: conversationID)
        } else {
            let rows = stride(from: 0, to: images.count, by: 2).map { Array(images[$0..<min($0 + 2, images.count)]) }
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row) { image in
                            RemoteImageView(image: image, conversationID: conversationID, square: true)
                        }
                        if row.count == 1 {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }
}

struct RemoteImageView: View {
    @Environment(ChatStore.self) private var store
    let image: RemoteImage
    let conversationID: String
    var square = false

    @State private var picture: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showsFull = false

    var body: some View {
        Color.clear
            .aspectRatio(square ? 1 : image.aspect, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                        Text("Нажмите, чтобы повторить")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(6)
                } else {
                    Spinner(size: 18, lineWidth: 2)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                if picture != nil {
                    showsFull = true
                } else if failed {
                    failed = false
                    attempt += 1
                }
            }
            .task(id: attempt) { await load() }
            .sheet(isPresented: $showsFull) {
                if let picture {
                    ScrollView {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: picture != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Изображение")
    }

    private func load() async {
        if let cached = store.gptHistory.cachedImage(image) {
            picture = cached
            return
        }
        do {
            picture = try await store.gptHistory.image(image, conversationID: conversationID)
        } catch {
            guard !GPTHistory.isCancellation(error) else { return }
            failed = true
        }
    }
}
