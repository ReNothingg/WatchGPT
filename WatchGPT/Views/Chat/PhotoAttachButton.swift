import PhotosUI
import SwiftUI

struct PhotoAttachButton: View {
    @Environment(ChatStore.self) private var store
    var size: CGFloat = 32

    var body: some View {
        Group {
            if !store.pendingImages.isEmpty {
                Button {
                    WKHaptics.click()
                    store.discardPendingImages()
                } label: {
                    PhotoStack(names: store.pendingImages, size: size)
                }
                .accessibilityLabel(store.pendingImages.count == 1 ? "Фото прикреплено" : "Прикреплено фото: \(store.pendingImages.count)")
                .accessibilityHint("Нажмите, чтобы убрать")
            } else if store.loadingPhotos {
                ProgressView()
                    .frame(width: size, height: size)
                    .glassBackground(Circle(), fill: Theme.raised)
                    .accessibilityLabel("Загрузка фото")
            } else {
                PhotosPicker(
                    selection: Bindable(store).photoSelection,
                    maxSelectionCount: Attachments.maxCount,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .glassBackground(Circle(), fill: Theme.raised, interactive: true)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Добавить фото")
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(store.isBusy)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: store.pendingImages)
        .animation(.easeOut(duration: 0.2), value: store.loadingPhotos)
    }
}

struct PhotoStack: View {
    let names: [String]
    let size: CGFloat

    private var shown: [String] { Array(names.prefix(3)) }

    var body: some View {
        let count = shown.count
        let card = count == 1 ? size : size * 0.74
        let radius = count == 1 ? size / 2 : card * 0.28
        ZStack {
            ForEach(Array(shown.enumerated().reversed()), id: \.element) { index, name in
                let depth = Double(index)
                AttachmentImage(name: name, pixels: Int(size * 3))
                    .frame(width: card, height: card)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(index == 0 ? Theme.accent : Color.black.opacity(0.6), lineWidth: index == 0 ? 1.5 : 1)
                    )
                    .brightness(-0.08 * depth)
                    .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
                    .rotationEffect(.degrees(angle(index, count)), anchor: UnitPoint(x: 0.5, y: 1.25))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Theme.accent))
                .offset(x: 4, y: -4)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: names)
    }

    private func angle(_ index: Int, _ count: Int) -> Double {
        switch (count, index) {
        case (2, 0): -7
        case (2, _): 11
        case (3, 1): 15
        case (3, 2): -15
        default: 0
        }
    }
}

struct AttachmentImage: View {
    let name: String
    var pixels = 160
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.raised
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .task(id: name) {
            let name = name
            let pixels = pixels
            let loaded = await Task.detached(priority: .userInitiated) { Attachments.thumbnail(name, maxPixels: pixels) }.value
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

struct AttachmentStrip: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                AttachmentImage(name: name, pixels: 180)
                    .frame(width: names.count == 1 ? 72 : 44, height: names.count == 1 ? 72 : 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(names.count == 1 ? "Фото" : "Фото: \(names.count)")
    }
}
