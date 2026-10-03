# FocusView

A minimal, locked-down video viewing browser for iPad, built entirely in
**Swift Playgrounds on iPad** (SwiftUI + WebKit, no third-party dependencies).

FocusView is a controlled viewer for pages you're already allowed to watch. It
does not bypass DRM, logins, paywalls or a site's security, and it doesn't
download media.

## Opening the project on iPad

1. In Safari on the iPad, open this repository on GitHub → **Code** → **Download ZIP**.
2. In the **Files** app, tap the ZIP to expand it.
3. Open `FocusView/FocusView.swiftpm`. It opens in Swift Playgrounds as an app project.
4. Tap ▶︎ **Run** to build and run it.

## Project layout

```
FocusView.swiftpm/
├── Package.swift              Swift Playgrounds app manifest
├── App/                       App entry point and root screen switching
├── Start/StartView.swift      URL entry start page
├── Viewer/                    Viewer screen, control bar, blocked toast
├── Web/
│   ├── BrowserController.swift   Owns the WKWebView, applies the policy, publishes state
│   └── WebViewContainer.swift    Puts the WKWebView into SwiftUI
└── Navigation/
    ├── NavigationPolicy.swift    The single place that allows/blocks navigation
    └── URLInputParser.swift      Turns typed text into a safe http(s) URL
```

SwiftUI views never talk to WebKit directly. `NavigationPolicy` doesn't import
WebKit, so the rules stay in one place and later phases can extend them
(the domain allowlist comes in Phase 2).

## Phase 1 status

Done:

- SwiftUI app with a start page (paste/enter a URL, Open)
- One WKWebView per viewer, with Back, Forward and Reload/Stop
- Back/Forward only move through that web view's own history
- Navigation interception: only `http`/`https` pages can load at the top level.
  `tel:`, `mailto:`, `itms-apps:` and other app links are blocked
- New windows are never created:
  - a **tapped** `target="_blank"` link loads in the current view
  - script popups (`window.open` without a link tap) are blocked
  - `javaScriptCanOpenWindowsAutomatically` is off
- Long-press link menu is replaced with a single in-app "Copy Link" option
- Responses that would become file downloads are blocked
- A small "Popup blocked" / "Navigation blocked" toast. It never takes over the screen
- Load errors show a small banner with Retry. The page reloads by itself if its web content process crashes

Not yet (later phases): domain allowlist and cross-domain redirect blocking
(Phase 2), bookmarks/history/settings (3), content blocking and privacy
controls (4), Video Mode, fullscreen and keep-awake (5).

## Phase 1 test checklist (run on the iPad)

| # | Test | Expected |
|---|------|----------|
| 1 | Type `example.com`, tap Open | Page loads over https. Toolbar shows `example.com` |
| 2 | Type `hello` or `javascript:alert(1)` | "That doesn't look like a web address." |
| 3 | Use the Paste button with a copied URL | The URL fills in the field |
| 4 | Follow a few links, then Back / Forward | Moves through history. Back is greyed out on the first page |
| 5 | Swipe from the left edge | Same as Back. Never leaves the app |
| 6 | Reload while loading | The button shows Stop while loading, Reload once loaded |
| 7 | Tap a `target="_blank"` link | Opens in the same view. No new window, no Safari |
| 8 | A page that calls `window.open` on load | Nothing opens. "Popup blocked" toast appears |
| 9 | Tap a `tel:` / `mailto:` / App Store link | Stays on the page. "Blocked link to another app" toast |
| 10 | Long-press a link | Only "Copy Link" is offered |
| 11 | Play an HTML5 video | Plays inline in the page |
| 12 | Turn on Airplane Mode, then Reload | Error banner with Retry |
| 13 | Tap ✕ | Back to the start page |

## About .ipa export

Swift Playgrounds can't export an `.ipa` file itself. Its built-in way to
install the app on devices is **App Settings → Upload to App Store Connect**
(TestFlight), which needs an Apple Developer account. If you specifically need
an `.ipa` file to sideload, the project is a standard app package, so a
hosted cloud build service can compile it without you owning a Mac. We can set
that up as a final step once the app is feature-complete.
