import ReelsGuardCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a Reel link from Instagram's share sheet (for example a Reel a
/// friend sent in a DM) and saves it to Reels Guard's local "Shared with me"
/// inbox. Only the URL is stored.
///
/// iOS gives share extensions no public API to launch their containing app,
/// so the user opens Reels Guard themselves to watch the Reel in the guarded
/// viewer, where it plays without a feed attached.
final class ShareViewController: UIViewController {
    private let store = SharedStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
            let url = await Self.firstInstagramURL(in: items)
            if let url { store.addToInbox(url) }
            show(ShareResultView(saved: url != nil) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
        }
    }

    private func show(_ view: ShareResultView) {
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    static func firstInstagramURL(in items: [NSExtensionItem]) async -> URL? {
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   let normalized = ReelLinkParser.normalize(url) {
                    return normalized
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let normalized = ReelLinkParser.instagramURL(in: text) {
                    return normalized
                }
            }
            if let text = item.attributedContentText?.string, let normalized = ReelLinkParser.instagramURL(in: text) {
                return normalized
            }
        }
        return nil
    }
}

private struct ShareResultView: View {
    let saved: Bool
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(saved ? "Saved to Reels Guard" : "Not an Instagram Reel")
                .font(.title3.weight(.semibold))
            Text(saved
                 ? "Open Reels Guard and tap Shared with me to watch it. It will play on its own, without a feed after it."
                 : "Share a link to a single Instagram Reel or post.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
