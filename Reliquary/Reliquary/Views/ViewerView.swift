import SwiftUI
import UIKit
import AVKit

struct ViewerContext: Identifiable {
    let id = UUID()
    let assets: [ImmichAsset]
    let startIndex: Int
}

struct ViewerView: View {
    let client: ImmichClient
    let assets: [ImmichAsset]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(client: ImmichClient, assets: [ImmichAsset], startIndex: Int) {
        self.client = client
        self.assets = assets
        let upper = max(assets.count - 1, 0)
        _index = State(initialValue: min(max(startIndex, 0), upper))
    }

    private var current: ImmichAsset? {
        return assets.indices.contains(index) ? assets[index] : nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { offset, asset in
                    AssetPageView(client: client, asset: asset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            topBar
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.crimsonBright)
                    .shadow(color: .black, radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(current?.displayName ?? "")
                    .font(Theme.title(14))
                    .foregroundColor(Theme.bone)
                    .lineLimit(1)
                if let date = current?.sortDate {
                    Text(ViewerView.dateFormatter.string(from: date))
                        .font(Theme.body(12))
                        .foregroundColor(Theme.muted)
                }
            }
            Spacer()
            if index > 0 {
                Button("Prev") { index -= 1 }
            }
            if index + 1 < assets.count {
                Button("Next") { index += 1 }
            }
            Text("\(index + 1) / \(assets.count)")
                .font(Theme.body(12))
                .foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

struct AssetPageView: View {
    let client: ImmichClient
    let asset: ImmichAsset

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if asset.isVideo {
                VideoPage(client: client, asset: asset)
            } else if let image = image {
                #if os(tvOS)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                ZoomableImageView(image: image)
                #endif
            } else if failed {
                ErrorStateView(message: "This relic could not be loaded.")
            } else {
                ProgressView().tint(Theme.crimsonBright)
            }
        }
        .task(id: asset.id) {
            if !asset.isVideo {
                await loadImage()
            }
        }
    }

    private func loadImage() async {
        // Show the cached grid thumbnail immediately while the larger preview loads.
        let previewKey = ImageStore.key(assetId: asset.id, size: .preview)
        let thumbKey = ImageStore.key(assetId: asset.id, size: .thumbnail)
        if let cachedPreview = ImageStore.shared.image(forKey: previewKey) {
            image = cachedPreview
            return
        }
        if let cachedThumb = ImageStore.shared.image(forKey: thumbKey) {
            image = cachedThumb
        }
        do {
            let data = try await client.imageData(assetId: asset.id, size: .preview)
            if Task.isCancelled { return }
            guard let decoded = UIImage(data: data) else {
                if image == nil { failed = true }
                return
            }
            ImageStore.shared.store(decoded, forKey: previewKey)
            image = decoded
        } catch {
            if !isCancellation(error) && image == nil {
                failed = true
            }
        }
    }
}

struct VideoPage: View {
    let client: ImmichClient
    let asset: ImmichAsset

    @State private var player: AVPlayer?
    @State private var unavailable = false

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
            } else if unavailable {
                ErrorStateView(message: "This video could not be opened.")
            } else {
                ProgressView().tint(Theme.crimsonBright)
            }
        }
        .onAppear { preparePlayer() }
        .onDisappear { player?.pause() }
    }

    private func preparePlayer() {
        if player != nil { return }
        guard let url = client.videoPlaybackURL(assetId: asset.id) else {
            unavailable = true
            return
        }
        let headers: [String: String] = ["x-api-key": client.apiKey]
        let avAsset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
    }
}

/// Pinch-to-zoom and double-tap-to-zoom image view backed by UIScrollView.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> ZoomHostView {
        let host = ZoomHostView()
        host.delegate = context.coordinator
        host.minimumZoomScale = 1
        host.maximumZoomScale = 5
        host.showsHorizontalScrollIndicator = false
        host.showsVerticalScrollIndicator = false
        host.bouncesZoom = true
        host.backgroundColor = .clear
        host.contentInsetAdjustmentBehavior = .never
        host.imageView.image = image

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        host.addGestureRecognizer(doubleTap)
        return host
    }

    func updateUIView(_ uiView: ZoomHostView, context: Context) {
        if uiView.imageView.image !== image {
            uiView.imageView.image = image
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            guard let host = scrollView as? ZoomHostView else { return nil }
            return host.imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let host = gesture.view as? ZoomHostView else { return }
            if host.zoomScale > 1.01 {
                host.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: host.imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: host.bounds.width / scale, height: host.bounds.height / scale)
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                host.zoom(to: rect, animated: true)
            }
        }
    }
}

final class ZoomHostView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(zoomScale - 1) < 0.0001 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }
}
