import AppKit
import Foundation
import UniformTypeIdentifiers

struct ImageAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let name: String

    var nsImage: NSImage? {
        NSImage(data: data)
    }

    var sizeDescription: String {
        guard let image = nsImage else { return "" }
        return "\(Int(image.size.width))×\(Int(image.size.height))"
    }
}

enum ImageSupport {
    static let maxBytes = 25 * 1024 * 1024

    static func normalizedPNG(from data: Data) -> Data? {
        guard data.count <= maxBytes,
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func imageData(from url: URL) -> Data? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return normalizedPNG(from: data)
    }

    static func readPasteboardImage() -> Data? {
        let pasteboard = NSPasteboard.general
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        for type in types {
            if let data = pasteboard.data(forType: type),
               let png = normalizedPNG(from: data) {
                return png
            }
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first,
           let png = imageData(from: first) {
            return png
        }
        return nil
    }

    static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let imageType = UTType.image.identifier
        let fileType = UTType.fileURL.identifier

        if provider.hasItemConformingToTypeIdentifier(imageType) {
            let imageData: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                    if let data, let png = normalizedPNG(from: data) {
                        continuation.resume(returning: png)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let imageData { return imageData }
        }
        if provider.hasItemConformingToTypeIdentifier(fileType) {
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: fileType, options: nil) { item, _ in
                    if let url = item as? URL,
                       let png = imageData(from: url) {
                        continuation.resume(returning: png)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              let png = imageData(from: url) {
                        continuation.resume(returning: png)
                    } else if let nsurl = item as? NSURL,
                              let png = imageData(from: nsurl as URL) {
                        continuation.resume(returning: png)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            return data
        }
        return nil
    }
}
