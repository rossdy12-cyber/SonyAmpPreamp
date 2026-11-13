import SwiftUI
import UIKit

/// In-memory decoded-image cache. The on-disk layer is URLCache (see ImmichClient.sharedCache).
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 800
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    static func key(assetId: String, size: ImageSize) -> String {
        return size.rawValue + "/" + assetId
    }

    func image(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Loads an Immich thumbnail or preview, using the memory cache first.
struct RemoteImage: View {
    let client: ImmichClient
    let assetId: String
    var size: ImageSize = .thumbnail
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.panel
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo")
                    .foregroundColor(Theme.hairline)
            }
        }
        .task(id: assetId) {
            await load()
        }
    }

    private func load() async {
        let key = ImageStore.key(assetId: assetId, size: size)
        if let cached = ImageStore.shared.image(forKey: key) {
            image = cached
            failed = false
            return
        }
        image = nil
        failed = false
        do {
            let data = try await client.imageData(assetId: assetId, size: size)
            if Task.isCancelled { return }
            guard let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            ImageStore.shared.store(decoded, forKey: key)
            image = decoded
        } catch {
            if !isCancellation(error) {
                failed = true
            }
        }
    }
}
