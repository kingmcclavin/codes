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
| **Open Instagram** (in-app browser) | instagram.com with the full policy: Reels tab and Explore Reels blocked; DM, profile and shared Reels allowed; swiping stops at the first Reel not from someone you follow. |
| **Safari extension** | Same rules on instagram.com in Safari, same settings. |
| **Share extension** | In the Instagram app, share a Reel a friend sent you to Reels Guard. It's saved to *Shared with me* and plays on its own. |
| **Screen Time lock** (optional) | Locks the native Instagram app, so you go through a filtered surface instead. |
| **Strict Mode** (optional) | Only followed accounts, plus Reels sent to you. Explore blocked. Turning it off requires typing a sentence and waiting 30 s. |
| **Reel time limit** (optional) | 5 / 10 / 15 / 30 minutes of Reels, then a cooldown. Other Instagram use isn't limited. |

The blocking screen is intentionally plain: a title, one sentence of
explanation, and a single **Back to Instagram** button. There is no "watch
anyway" and no "next Reel" button.

## Build

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
├── Packages/ReelsGuardCore/        Foundation-only policy package + tests
├── Shared/WebGuard/                reels-observer.js (shared) + Node tests
├── App/Sources/                    SwiftUI companion app
│   ├── Browser/                    guarded WKWebView
│   ├── ScreenTime/                 FamilyControls / ManagedSettings
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
