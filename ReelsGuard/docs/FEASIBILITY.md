# What is and isn't possible on stock iOS

This document records the investigation done before implementation. It
separates what Reels Guard actually does from what would need private APIs, a
jailbreak or a modified Instagram, none of which it uses.

## The core constraint

The requested behavior ("is the next Reel from someone I follow?") requires
knowing which Reel is on screen, who posted it, and how the user got there.

**iOS gives third-party apps no supported way to observe or change another
app's UI.** Every app is sandboxed. There is no public accessibility,
screen-reading, or UI-injection API for other apps. So **Reels Guard cannot
filter Reels inside the native Instagram app**, and it doesn't pretend to.

The only place where Reel-level information is available through supported
APIs is **instagram.com, rendered by a web engine that Reels Guard controls or
extends**:

- a `WKWebView` inside the Reels Guard app, and
- Safari, through a Safari Web Extension.

In both, page URLs are visible, and a script running in an isolated JavaScript
world can read the page that the user is looking at.

## Mechanisms investigated

| Mechanism | Can it identify an individual Reel? | Used? | Notes |
|---|---|---|---|
| **WKWebView + WKContentWorld script** (in-app browser) | Yes: URL, creator link, Follow button | **Yes, primary** | Full control: pause media, overlay, cancel navigations. |
| **Safari Web Extension** (content script + native messaging) | Yes, same as above | **Yes** | Same engine via `SafariWebExtensionHandler`. User must enable it in Settings. |
| **Share extension** | Gets the link the user shares | **Yes** | Lets Reels sent in the native app's DMs be watched without a feed. Can't open the containing app (no public API), so links go to an inbox. |
| **URL scheme** (`reelsguard://open?url=`) | Gets a link passed to it | **Yes** | For Shortcuts and other apps. |
| **FamilyControls + ManagedSettings** (Screen Time) | No. Whole apps only, as opaque tokens | **Yes, optional** | Locks the entire native Instagram app as a commitment device. |
| **ShieldConfiguration / ShieldAction extensions** | No | **Yes** | Custom lock-screen text. Shield buttons can only close or defer; they can't open another app. |
| **Shortcuts personal automation** ("When Instagram is opened → Open Reels Guard") | No | **Documented** | Public and effective, but only the user can create it. Apps can't install automations. |
| **DeviceActivity** (monitor / report) | No. Usage totals per app token, no in-app detail; report extensions can't export data | No | The Reel time limit only needs Reel watch time, which the web surfaces measure directly. A schedule could auto-unlock Instagram after a cooldown. That's a possible extension, not needed now. |
| **Safari Content Blocker** (`WKContentRuleList`) | URL patterns only, at request time | No | Can't see in-page (`pushState`) navigation or follow state. The web extension already covers it. |
| **Network Extension content filter / VPN** | No | No | Instagram traffic is TLS with certificate pinning; Reels and other content share hosts and CDNs. Filters see hostnames, not Reels. Content filters also need supervision or Screen Time entitlements, and inspecting traffic would conflict with the privacy goals. |
| **Universal Links interception** | — | No | instagram.com links belong to Instagram's app; other apps can't claim them. |
| **Instagram APIs** (Graph / Basic Display) | No | No | Basic Display was retired in December 2024. The Graph API covers only a business/creator account's own media, with no follow list and no feed. So there is no official way to fetch "accounts I follow". |
| **Private APIs, code injection, modified IPA, jailbreak tweaks** | Yes | **No, out of scope by requirement** | This is the only way to filter the native app's Reels viewer. |

## Requirement-by-requirement status

Legend: ✅ implemented · ⚠️ best effort / heuristic · ❌ not possible on stock iOS

| Requirement | In-app browser | Safari | Native Instagram app |
|---|---|---|---|
| Allow Reel opened from a DM | ✅ | ✅ | ⚠️ Share it to Reels Guard, watch in-app |
| Allow Reel opened from a profile | ✅ | ✅ | ❌ |
| Allow Reel from a followed account | ⚠️ follow detection | ⚠️ | ❌ |
| Allow explicitly shared Reel | ✅ inbox / URL scheme | ✅ fresh tab | ✅ via share extension |
| Block Reels tab (`/reels/`) | ✅ | ✅ | ❌ (whole-app lock only) |
| Block Explore / suggested Reels | ✅ | ✅ | ❌ |
| Stop swipe chain at first non-followed Reel | ✅ | ✅ | ❌ |
| Blocking screen with only "Back to Instagram" | ✅ native overlay | ✅ injected overlay | Screen Time shield (different text, "OK" only) |
| Strict Mode with deliberate disable | ✅ | ✅ (shared settings) | ✅ can also hold the app lock on |
| Reel time limit + cooldown | ✅ | ✅ | ❌ (Reel time isn't observable) |
| Regular Instagram unaffected by limit | ✅ | ✅ | ✅ (not touched) |
| No data leaves the device | ✅ | ✅ | ✅ |

### How follow status is determined (⚠️)

There is no API for "does the user follow @x". Reels Guard combines, in order:

1. **Accounts I Follow (manual)**: usernames the user adds.
2. **Learned from profiles**: when the user visits a profile on instagram.com,
   the observer reads the header button. "Following" adds the account and
   "Follow" removes it. On by default, local only, can be cleared.
3. **On-page hint next to the Reel**: a visible "Follow" button means *not
   followed*, and a "Following" label means followed. A missing button proves
   nothing and counts as unknown.

When none of these can confirm a follow, **the next Reel is blocked** (fail
closed). The cost is that some followed accounts' Reels will occasionally be
interrupted until they're learned or added. The detection reads English UI
labels only, and depends on Instagram's markup, which changes without notice.
All selectors are in one section of `Shared/WebGuard/reels-observer.js`.

### How "intentional" is determined

The engine remembers the last non-Reel page in the tab:

| Previous page | Entry source | Default |
|---|---|---|
| none (fresh tab, shared link, inbox) | shared link | allow |
| `/direct/…` | direct message | allow |
| `/<username>/…` | profile | allow (Strict: only if followed) |
| `/` home feed | home feed | allow unless a Follow button is shown (Strict: only if followed) |
| `/explore/…`, `/reels/` | recommended | block |
| anything else | other | allow only if followed |

Once a Reel is allowed, every *different* Reel that follows without leaving
Reels is a **continuation**. A continuation is detected when any of these happen
after the user touches or scrolls:

- the URL changes to another Reel,
- the on-screen player becomes a different `<video>`, or the same one switches
  source,
- the Reel scroller moves by more than 60 % of a screen.

A Reel that was **sent to the user** (DM or shared link) plays on its own: any
continuation after it is blocked, whoever posted the next one. After a Reel
opened from a profile or the home feed, a continuation is allowed only if the
creator is followed, or is the same creator whose profile the chain started on.

On DM pages, a Reel may open full screen over the conversation without a URL
change. The observer recognises it by the size of the playing video alone and
reads no names or text there.

## Other known limitations

- **Instagram's website.** Instagram may change, limit, or require the app for
  features on its mobile website at any time. Reels Guard can't control that.
- **Inline videos in the home feed** are left alone. They're part of regular
  Instagram, not the Reels viewer. Opening one in the Reels viewer is checked.
- **Safari extension** fails open if its native handler is unavailable, so
  Instagram is never left broken. The in-app browser can't fail this way,
  because the engine runs in the same process.
- **Screen Time "individual" authorization** can be revoked by the user in
  Settings. This is a commitment device, not a parental control.
- **Family Controls entitlement:** distributing an app that uses FamilyControls
  requires requesting the entitlement from Apple. Development builds work
  without it.

## Swift Playgrounds (iPad) build

Swift Playgrounds builds a single app target. It can't build app extensions,
and it can't add the Family Controls or App Group entitlements. The
`ReelsGuard.swiftpm` build therefore contains only the in-app browser, which
is the surface with the most complete filtering anyway:

| Feature | Xcode build | Playgrounds build |
|---|---|---|
| Filtered in-app Instagram browser | ✅ | ✅ |
| Settings, Strict Mode, Reel time limit, follow list | ✅ | ✅ |
| Shared with me | ✅ share sheet or paste | ✅ paste only |
| Safari extension | ✅ | ❌ needs an app extension |
| Share extension | ✅ | ❌ needs an app extension |
| Screen Time lock and shield | ✅ | ❌ needs extensions and the Family Controls entitlement |

## Web app

A website can't do what the iOS app does. instagram.com sends headers that
forbid other sites from framing it, and browsers isolate cross-origin pages, so
no web page can show Instagram's feed, read its pages, or interrupt its
scrolling. A proxy that relayed instagram.com through a server would have to
carry the user's Instagram login, which the privacy requirements rule out.

The one supported way to show Instagram content on another website is the
**official embed player** (`/reel/<code>/embed/`). It shows a single Reel or
post with nothing after it. The web app (`Web/`) is built on it:

| Feature | Web app |
|---|---|
| Watch a Reel someone sent (paste the link) | ✅ one Reel, no feed |
| Links inside the player opening Instagram | ❌ blocked by the frame sandbox |
| Daily Reel time limit + cooldown | ✅ counts time a Reel is open (playback inside the player can't be observed) |
| Filtering the feed, profiles, Explore, DMs | ❌ not possible on the web |
| Private accounts / embedding disabled | ❌ Instagram shows a notice instead |
| Share sheet → app | Android (Web Share Target) only; iOS doesn't support it for web apps, so copy and paste the link |
