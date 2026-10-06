# Reels Guard

An iOS companion app that lets you watch Instagram Reels you **chose** (sent
in a DM, opened from a profile, or posted by someone you follow) while stopping
Instagram from turning them into an endless recommendation feed.

> Watch what you intentionally choose. Stop Instagram from automatically feeding you more.

**Read [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) first.** iOS doesn't let
any app inspect or modify the native Instagram app, so Reels Guard does its
Reel-level filtering on **instagram.com**, in its own browser and in Safari.
For the native app it offers only what Screen Time allows: locking the whole
app. It uses no private APIs, no code injection and no jailbreak.

## What it does

| Surface | What happens |
|---|---|
| **Instagram tab** (opens on launch) | instagram.com with the full policy: Reels tab and Explore Reels blocked; DM, profile and shared Reels allowed; swiping stops at the first Reel not from someone you follow. |
| **Safari extension** | Same rules on instagram.com in Safari, same settings. |
| **Share extension** | In the Instagram app, share a Reel a friend sent you to Reels Guard. It's saved to *Shared with me* and plays on its own. |
| **Screen Time lock** (optional) | Locks the native Instagram app, so you go through a filtered surface instead. |
| **Strict Mode** (optional) | Only followed accounts, plus Reels sent to you. Explore blocked. Turning it off requires typing a sentence and waiting 30 s. |
| **Reel time limit** (optional) | 5 / 10 / 15 / 30 minutes of Reels, then a cooldown. Other Instagram use isn't limited. |

The blocking screen is intentionally plain: a title, one sentence of
explanation, and a single **Back to Instagram** button. There is no "watch
anyway" and no "next Reel" button.

## Run it on an iPad (Swift Playgrounds, no Mac needed)

`ReelsGuard.swiftpm` is a Swift Playgrounds app. It contains the in-app
filtered Instagram browser, every setting, Strict Mode, the Reel time limit,
*Shared with me* and the follow list.

It **doesn't** contain the Safari extension, the share extension or the Screen
Time lock. Swift Playgrounds can't build app extensions or use Apple's Family
Controls entitlement, so those need the full Xcode project on a Mac. To
watch a Reel someone sent you, copy its link in Instagram and paste it into
*Shared with me*.

1. On the iPad, open this link in Safari (sign in to GitHub if asked):
   `https://github.com/kingmcclavin/codes/archive/refs/heads/claude/reels-guard-ios.zip`
2. In the **Files** app, open **Downloads** and tap the ZIP to unzip it.
3. Open the unzipped folder, then `ReelsGuard`, and tap **`ReelsGuard.swiftpm`**.
   It opens in Swift Playgrounds. Requires iPadOS 17+ and a recent Swift Playgrounds.
4. Tap **Run** (▶). The app opens straight into Instagram; sign in on
   instagram.com. Settings are in the second tab.

The app runs inside Swift Playgrounds. Putting it on your Home Screen or on an
iPhone means publishing it through App Store Connect / TestFlight (Swift
Playgrounds can do this from the iPad). That requires a paid Apple Developer
Program membership.

The `.swiftpm` folder is generated. When developing, edit the originals and run
`scripts/build-playgrounds-app.py` (`--check` verifies it's current).

## Get an .ipa (no Mac needed)

Every push to this branch builds the app on a GitHub-hosted Mac
(`.github/workflows/reels-guard-ios.yml`) and publishes two **unsigned**
`.ipa` files on the repository's **Releases** page under
**Reels Guard (latest build)**:

| File | Contents |
|---|---|
| `ReelsGuard-Lite-unsigned.ipa` | Instagram tab + Settings, no extensions or entitlements. **Use this one for sideloading.** |
| `ReelsGuard-Full-unsigned.ipa` | Also has the Safari, share and Screen Time extensions. With a free Apple ID, sideloading tools generally can't grant Screen Time (Family Controls) or App Groups, so those parts may not work. |

An unsigned `.ipa` must be signed when it's installed. Sideloading tools
(AltStore, SideStore, Sideloadly and similar) do this with your Apple ID.
With a free Apple ID the app expires after 7 days and must be refreshed. A paid
developer account lasts a year. Once the workflow is on the default branch, you can also run it by hand from the
**Actions** tab (**Run workflow**).

## Build the full version (Mac + Xcode)

Requirements: Xcode 15+, iOS 17+ device (Screen Time APIs don't work in the
simulator), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd ReelsGuard
xcodegen generate
open ReelsGuard.xcodeproj
```

Then:

1. Replace `com.example` bundle ids and the App Group
   `group.com.example.reelsguard` in `project.yml` **and**
   `Packages/ReelsGuardCore/Sources/ReelsGuardCore/SharedStore.swift`.
2. Set your development team.
3. Run the `ReelsGuard` scheme on a device.
4. Optional: enable the Safari extension (Settings → Apps → Safari → Extensions).

Tests:

```sh
# Policy engine, classifier, persistence (macOS or Linux, Swift 5.9+)
cd Packages/ReelsGuardCore && swift test

# Page observer script, against simulated Instagram DOM (Node 18+)
cd Shared/WebGuard && npm install && npm test
```

## Architecture

```
                 ┌──────────────── instagram.com page ────────────────┐
                 │  reels-observer.js (isolated JS world)             │
                 │  reports: page URL · active Reel · creator ·       │
                 │           Follow-button hint · watch ticks         │
                 └───────────────┬───────────────────────▲────────────┘
                     WireRequest │                       │ WireResponse
          ┌──────────────────────┴───┐        ┌──────────┴────────────────────┐
          │ In-app browser            │        │ Safari extension               │
          │ GuardedBrowserModel       │        │ content.js → background.js →   │
          │ (WKScriptMessageHandler)  │        │ SafariWebExtensionHandler      │
          └──────────────┬────────────┘        └──────────────┬─────────────────┘
                         └──────────────┬────────────────────┘
                                        ▼
                      ReelsGuardService (ReelsGuardCore)
                      ├─ InstagramURLClassifier  URL → PageKind
                      ├─ FollowResolver          known follows + page hint
                      ├─ ReelsGuardEngine        pure: (event, state) → decision
                      │    rules: Page → TimeBudget → CurrentReel →
                      │           Continuation → Entry → (fail closed)
                      └─ SharedStore             App Group: settings, timer, inbox
```

```
ReelsGuard/
├── project.yml                     XcodeGen spec (app + 4 extensions)
├── ReelsGuard.swiftpm/             GENERATED Swift Playgrounds app (iPad)
├── PlaygroundsSupport/             Playgrounds-only manifest and Platform/ files
├── scripts/build-playgrounds-app.py  regenerates the two generated outputs
├── Packages/ReelsGuardCore/        Foundation-only policy package + tests
├── Shared/WebGuard/                reels-observer.js (shared) + Node tests
├── App/Sources/                    SwiftUI companion app
│   ├── Browser/                    guarded WKWebView (+ generated ObserverScript.swift)
│   ├── Platform/                   App entry, Screen Time, Safari setup: swapped out in Playgrounds
│   ├── Model/                      settings view model
│   └── Views/                      control screen, block screen, etc.
├── Extensions/
│   ├── SafariWeb/                  Safari Web Extension (MV3) + native handler
│   ├── Share/                      share extension → "Shared with me"
│   ├── ShieldConfiguration/        Screen Time shield text
│   └── ShieldAction/               Screen Time shield button
└── docs/FEASIBILITY.md             what is / isn't possible, and why
```

### Extending it

- **A new filtering rule** (for example a daily Reel count or a creator
  blocklist): implement `GuardRule` and insert it into
  `ReelsGuardEngine.defaultRules`. Rules see only a `GuardContext` (page kind,
  Reel id, creator, follow state, settings, timer), never raw page content.
- **A new enforcement surface** (for example a macOS Safari build): run
  `reels-observer.js` in the page and forward its messages to
  `ReelsGuardService.handle(_:state:)` or `handleStateless(_:)`.
- **Instagram markup changes**: update the "DOM heuristics" section of
  `reels-observer.js`; the tests in `Shared/WebGuard/tests` describe the
  expected behaviour.

## Privacy

- No account, server, analytics, ads, notifications or engagement metrics.
- All decisions are made on the device. Nothing about Instagram use is sent
  anywhere. The only network traffic is the web view talking to Instagram.
- You sign in on instagram.com itself. Reels Guard never reads form fields,
  passwords, or DM contents. On `/direct/` pages the observer only notes the
  page type.
- Stored locally: settings, the Reel timer (only when a limit is on), links
  you shared into the app, and the follow list you built.
- Screen Time returns opaque tokens. Reels Guard can't tell which app you
  picked or how you use it.
