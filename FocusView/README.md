# FocusView

A browser for iPad that blocks ads, popups and ad redirects on the video and
livestream sites you already use. It's built entirely in **Swift Playgrounds
on iPad** (SwiftUI + WebKit, no third-party dependencies).

The site's own player plays the video. FocusView doesn't bypass logins,
paywalls or DRM, and it doesn't download media.

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
├── Start/StartView.swift      Start page (enter a site or link)
├── Viewer/                    Browser screen, control bar, shield menu, blocked toast
├── Web/
│   ├── BrowserController.swift   Owns the WKWebView, applies rules and policy, publishes state
│   └── WebViewContainer.swift    Puts the WKWebView into SwiftUI
├── Blocking/
│   ├── AdBlockRules.swift        Ad/popunder/tracker domains and hidden ad elements
│   └── ContentBlocker.swift      Compiles the rules into a WKContentRuleList
└── Navigation/
    ├── NavigationPolicy.swift    The single place that allows/blocks popups and redirects
    ├── SiteIdentity.swift        Decides whether two URLs are the same site
    └── URLInputParser.swift      Turns typed text into a safe http(s) URL
```

SwiftUI views never talk to WebKit directly. The blocking rules and the
navigation policy don't import WebKit, so they're easy to read and extend.

## How the blocking works

FocusView uses three layers:

1. **Ad blocking (WebKit content blocker).** WebKit blocks requests to about
   60 known ad, popunder and tracker networks before they load. It also hides
   common ad slots (`.adsbygoogle`, GPT ad divs, ad iframes). The list
   deliberately leaves out video CDNs and player providers so playback keeps
   working. It's in `Blocking/AdBlockRules.swift`.
2. **Popup blocking.** The app never creates a second window.
   - Script popups (`window.open`, popunders) are blocked.
   - A tapped `target="_blank"` link opens in place if it stays on the same site.
   - A `target="_blank"` link to a different site counts as a popup and is
     blocked. Invisible "click anywhere" ad overlays use exactly this trick.
3. **Ad-redirect blocking.** A page can't move you to a different site by
   itself, and neither can a tap inside an embedded ad frame. Links you tap,
   forms, Back/Forward/Reload and the server redirects that follow them still
   work normally.

Blocked popups and redirects show a small toast, for example "Popup blocked:
ads.example.net". The toast has an **Open** button in case the page was one
you wanted. Links to other apps (`tel:`, `mailto:`, App Store) and downloads
are always blocked.

The **shield** in the top bar shows how many popups and redirects were
blocked. If a site ever breaks, open the shield menu and turn off
**Block Ads** for that tab.

## Phase 1 test checklist (run on the iPad)

| # | Test | Expected |
|---|------|----------|
| 1 | Type `example.com`, tap Open | Page loads over https. Shield is highlighted |
| 2 | Type `hello` or `javascript:alert(1)` | "That doesn't look like a web address." |
| 3 | Open a streaming site with ads, play a video or livestream | Video plays. Ad slots are missing or empty |
| 4 | Tap the video or the page background on a popup-heavy site | No new window. "Popup blocked" toast. Shield count goes up |
| 5 | Tap "Open" on a toast | The blocked page loads in the same view |
| 6 | Wait on a page that redirects itself to an ad site | Stays on the page. "Redirect blocked" toast |
| 7 | Tap a normal link to another site | It opens (links you tap are allowed) |
| 8 | Follow links, then Back / Forward / swipe from the edge | Moves through history. Back is greyed out on the first page |
| 9 | Shield menu → turn off Block Ads | Page reloads with ads. Turning it back on removes them |
| 10 | Tap a `tel:` / `mailto:` / App Store link | Stays on the page. "Blocked link to another app" toast |
| 11 | Long-press a link | Only "Copy Link" is offered |
| 12 | Turn on Airplane Mode, then Reload | Error banner with Retry |
| 13 | Tap the house icon | Back to the start page |

If a site's video stops working, turn off Block Ads in the shield menu. If
that fixes it, tell me the site's domain and I'll adjust the rules.

## Roadmap

- **Phase 2:** per-site settings (remember "ads off" for a site, always
  allow popups or redirects to a trusted domain) and a bigger, updatable
  filter list
- **Phase 3:** bookmarks, history, settings screen, local persistence
- **Phase 4:** privacy controls (clear history, cookies, website data, cache)
- **Phase 5:** fullscreen video, a mode that hides the toolbar, keep the
  screen awake, iPad layout polish
- **Phase 6:** full on-device test pass

## About .ipa export

Swift Playgrounds can't export an `.ipa` file itself. Its built-in way to
install the app on devices is **App Settings → Upload to App Store Connect**
(TestFlight), which needs an Apple Developer account. If you specifically need
an `.ipa` file to sideload, the project is a standard app package, so a
hosted cloud build service can compile it without you owning a Mac. We can set
that up as a final step once the app is feature-complete.
