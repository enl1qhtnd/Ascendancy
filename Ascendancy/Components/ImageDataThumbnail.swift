import ImageIO
import SwiftUI
import UIKit

struct ImageDataThumbnail<ID: Equatable, Placeholder: View>: View {
    let id: ID
    let data: Data
    let size: CGSize
    let cornerRadius: CGFloat
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: id) {
            let maxPixelSize = max(size.width, size.height) * UIScreen.main.scale
            image = await ImageDataThumbnailRenderer.thumbnail(from: data, maxPixelSize: maxPixelSize)
        }
    }
}

private enum ImageDataThumbnailRenderer {
    static func thumbnail(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            downsample(data: data, maxPixelSize: maxPixelSize)
        }.value
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
