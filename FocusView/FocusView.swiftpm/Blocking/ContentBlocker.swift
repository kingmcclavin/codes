import Foundation
import WebKit

/// Compiles `AdBlockRules` into a WKContentRuleList once and hands it to
/// every browser. WebKit then blocks matching requests and hides matching
/// elements itself, before the page ever sees them.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private var compiled: WKContentRuleList?
    private var didFail = false

    private init() {}

    /// The compiled ad-blocking rules, or nil if WebKit rejected them (the
    /// browser then still works, with popup and redirect blocking only).
    func ruleList() async -> WKContentRuleList? {
        if let compiled { return compiled }
        if didFail { return nil }

        let list = await withCheckedContinuation { (continuation: CheckedContinuation<WKContentRuleList?, Never>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: AdBlockRules.identifier,
                encodedContentRuleList: AdBlockRules.json()
            ) { list, error in
                if let error {
                    print("FocusView: ad block rules failed to compile: \(error)")
                }
                continuation.resume(returning: list)
            }
        }

        compiled = list
        didFail = (list == nil)
        return list
    }
}
