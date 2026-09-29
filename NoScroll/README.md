# NoScroll — iOS Swift package

The iPhone app from [Blueturboguy07/noscroll](https://github.com/Blueturboguy07/noscroll)
(`ios/` at commit `17bda4c`), repackaged as a Swift package plus a thin Xcode host app.

NoScroll wraps Instagram, YouTube and friends in a WKWebView and injects a small engine that
removes Reels, Shorts, Explore and suggested feeds. See the original repo for the full story.

## Layout

```
Package.swift
Sources/
  NoScrollCore/     Pure logic: sleep schedule, life-in-weeks maths, SVG path parser
  NoScrollKit/      The whole app: onboarding, tabs, web wrapper, signed rule bundles
    Resources/      noscroll.js (the blocking engine), Rules/*.json, rules-signing.pub.raw
  NoScrollWidgets/  Home-screen shortcuts widget
  NoScrollShield/   Screen Time extensions (shield screen, shield buttons, schedule monitor)
Tests/
  NoScrollCoreTests/
App/                Xcode host: @main entry points, Info.plists, entitlements, app icon
  project.yml       XcodeGen spec that generates NoScroll.xcodeproj
```

A Swift package can't produce an installable `.app` with app extensions by itself, so the
`App/` folder holds the few files that must live in an Xcode target. Everything else is in the
package.

## No Mac? Install from GitHub Actions

The workflow `.github/workflows/noscroll-ios.yml` builds the app on a GitHub-hosted Mac on every
push that touches `NoScroll/` (or on demand from the Actions tab → *NoScroll iOS* → *Run workflow*).

1. Open the latest successful *NoScroll iOS* run and download the **NoScroll-ipa** artifact.
   Unzip it to get `NoScroll.ipa`. (It's unsigned; the next step signs it.)
2. On a Windows PC, install [Sideloadly](https://sideloadly.io) (it needs iTunes and iCloud from
   Apple's website, not the Microsoft Store versions). AltStore (altstore.io) works too.
3. Plug in your iPhone, drag `NoScroll.ipa` into Sideloadly, enter your Apple ID and press Start.
4. On the iPhone: *Settings → General → VPN & Device Management* → trust your Apple ID, and turn
   on *Settings → Privacy & Security → Developer Mode* when asked (iPhone restarts).

With a free Apple ID the app expires after 7 days; re-sideload it (Sideloadly can auto-refresh
over Wi-Fi). A paid Apple Developer account ($99/yr) extends that to a year.

## Run it on your iPhone from a Mac

Requires Xcode 15+ and iOS 17+.

### Option A — XcodeGen (quickest)

```bash
brew install xcodegen
cd App
xcodegen
open NoScroll.xcodeproj
```

In Xcode, select the **NoScroll** target → *Signing & Capabilities* → pick your team (do the same
for **NoScrollWidget**). If the bundle ID `app.noscroll` is taken, change it (and the widget's
`app.noscroll.widget`) to something of yours. Plug in your iPhone, choose it as the run
destination, press **Run**.

On first run on a device, trust the developer profile under *Settings → General → VPN & Device
Management*, and turn on *Developer Mode* if iOS asks.

### Option B — plain Xcode, no extra tools

1. *File → New → Project → iOS App* (SwiftUI, Swift). Name it NoScroll, iOS 17 minimum.
2. *File → Add Package Dependencies… → Add Local…* and choose this folder. Add the
   **NoScrollKit** library to the app target.
3. Replace the generated `…App.swift` with [`App/NoScroll/NoScrollApp.swift`](App/NoScroll/NoScrollApp.swift):
   ```swift
   import NoScrollKit
   import SwiftUI

   @main
   struct NoScrollApp: App {
       var body: some Scene { NoScrollScene() }
   }
   ```
   Delete the generated `ContentView.swift`.
4. In the target's *Info* tab add the keys from [`App/NoScroll/Info.plist`](App/NoScroll/Info.plist):
   camera, microphone and photo-library usage strings (needed to post from the web), and the
   `noscroll` URL scheme (used by the widget).
5. Optional: drag `App/NoScroll/Assets.xcassets/AppIcon.appiconset/icon-1024.png` into AppIcon.
6. Optional widget: *File → New → Target → Widget Extension*, add the **NoScrollWidgets** library
   to it, and replace its bundle with [`App/NoScrollWidget/NoScrollWidgetBundle.swift`](App/NoScrollWidget/NoScrollWidgetBundle.swift).

## Screen Time shield (optional, needs Apple approval)

Blocking the real Instagram/YouTube apps uses Apple's `com.apple.developer.family-controls`
entitlement, which Apple must grant to your developer account first (it can take weeks and can
be denied). Without it the app still works as the wrapper — the Shield tab explains that
rather than failing.

Once granted:

- set `NOSCROLL_ENTITLEMENTS` on the NoScroll target to `NoScroll/NoScroll.entitlements`, and
- uncomment the three Screen Time extension targets (and the matching dependencies) in
  `App/project.yml`, then re-run `xcodegen`.

Screen Time never works in the Simulator; test it on a real device.

## Tests

```bash
xcodebuild test -scheme NoScroll-Package -destination 'platform=iOS Simulator,name=iPhone 16'
```

or open `Package.swift` in Xcode and press ⌘U with an iPhone simulator selected.

## Updating the engine and rules

`Sources/NoScrollKit/Resources/noscroll.js` and `Rules/*.json` are build outputs of the original
repo (`engine/` and `rules/`). To refresh them, build there (`cd engine && pnpm install && pnpm build`)
and copy `engine/dist/noscroll.js` and `rules/*.json` over the files here. Rule bundles are
ed25519-signed; ones that fail verification against `rules-signing.pub.raw` are refused.

## Changes from the original `ios/` code

- `@main` moved out of the library: the app is exposed as `NoScrollScene` / `NoScrollRootView`,
  the widget as `NoScrollWidget`.
- Bundled resources load from `Bundle.module` instead of `Bundle.main`; rule bundles now always
  come from the `Rules/` subdirectory.
- The Screen Time extension classes are `open` (`NoScrollShieldConfiguration`,
  `NoScrollShieldActionHandler`, `NoScrollActivityMonitor`); each extension target subclasses one.
- Files that used `NoScrollCore` types now `import NoScrollCore` (the original app compiled those
  sources straight into the app target).

## Licence

AGPL-3.0-or-later, same as the original project. See [LICENSE](LICENSE).
