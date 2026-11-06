import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Attachments {
    static let maxPixels = 1280
    static let maxCount = 4

    static let directory: URL = {
        let dir = AppFiles.url("Attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(_ name: String) -> URL {
        directory.appending(path: name)
    }

    static func save(_ data: Data) -> String? {
        guard let jpeg = jpeg(from: data) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: url(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func jpeg(from data: Data, maxPixels: Int = maxPixels, quality: Double = 0.75) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = scaled(source, maxPixels: maxPixels) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func thumbnail(_ name: String, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(name) as CFURL, nil) else { return nil }
        return scaled(source, maxPixels: maxPixels)
    }

    static func base64(_ name: String) -> String? {
        (try? Data(contentsOf: url(name)))?.base64EncodedString()
    }

    static func remove(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: url(name))
        }
    }

    static func prune(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path()) else { return }
        remove(files.filter { !names.contains($0) })
    }

    private static func scaled(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
