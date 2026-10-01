import Foundation
import ReelsGuardCore
import SafariServices

/// Native side of the Safari web extension. Receives observer messages from
/// `background.js` and runs them through the shared policy engine. The tab's
/// navigation state travels with each message (`stateJSON`), so this handler
/// is stateless; settings and the Reel time budget come from the App Group.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let service = ReelsGuardService()

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        let reply = NSExtensionItem()
        reply.userInfo = [SFExtensionMessageKey: service.handleStateless(message: message)]
        context.completeRequest(returningItems: [reply], completionHandler: nil)
    }
}
