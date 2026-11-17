import Foundation
import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - URLSession download delegate

final class DLDelegate: NSObject, URLSessionDownloadDelegate {
    weak var model: BrowserModel?
    init(model: BrowserModel) { self.model = model }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let t = model?.taskToDownload[downloadTask] else { return }
        DispatchQueue.main.async {
            t.progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let t = model?.taskToDownload[downloadTask] else { return }
        let dir = DataStore.shared.downloadsDir
        var name = t.filename
        var i = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            i += 1
        }
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            t.filename = name
            t.localURL = dest
            DispatchQueue.main.async {
                t.done = true
                t.progress = 1
                DataStore.shared.upsertDownload(DownloadEntry(id: t.id, filename: name, url: t.url.absoluteString, date: Date(), completed: true))
                BrowserModel.shared.showToast("Saved \(name)")
            }
        } catch {
            DispatchQueue.main.async { t.done = false }
        }
        model?.taskToDownload.removeValue(forKey: downloadTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let t = model?.taskToDownload[task] else { return }
        DispatchQueue.main.async {
            BrowserModel.shared.showToast("Download failed: \(error.localizedDescription)")
        }
        model?.taskToDownload.removeValue(forKey: task)
    }
}

// MARK: - Web container (hosts all tab webviews, shows active)

struct WebContainer: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let tab = model.activeTab else { return }
        let wv = model.ensureWebView(tab)
        if wv.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            uiView.addSubview(wv)
            wv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: uiView.topAnchor),
                wv.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: uiView.trailingAnchor)
            ])
        }
    }
}

// MARK: - Snapshots for the tab switcher

struct TabSnapshotView: View {
    @ObservedObject var tab: Tab
    var body: some View {
        Group {
            if let img = tab.snapshot {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Gothic.ember.opacity(0.4)
                    Image(systemName: "safari")
                        .font(.system(size: 34))
                        .foregroundColor(Gothic.crimson)
                }
            }
        }
    }
}
