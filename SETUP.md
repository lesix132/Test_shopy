# JobTrack — Xcode setup

This project ships as source + an **XcodeGen** spec so the `.xcodeproj` (with its
app target, Share Extension and test target) is generated deterministically
instead of being committed. Follow the steps below on a Mac with **Xcode 16+**
(the project format emitted by the current XcodeGen requires Xcode 16 or newer).

---

## 1. Generate the project

```bash
brew install xcodegen        # one-time
cd path/to/repo
xcodegen generate            # reads project.yml → creates JobTrack.xcodeproj
open JobTrack.xcodeproj
```

> No XcodeGen? You can instead create an empty *Multiplatform App* in Xcode named
> `JobTrack`, then drag the `JobTrack/`, `Shared/`, and `ShareExtension/` folders
> in and add an *App Extension* + *Unit Test* target. XcodeGen is strongly
> recommended — it wires all of this for you.

## 2. Set your signing team

XcodeGen leaves `DEVELOPMENT_TEAM` empty. In Xcode:

1. Select the **JobTrack** project → each target → **Signing & Capabilities**.
2. Pick your **Team**. Do this for **JobTrack** *and* **ShareExtension**.
3. Let Xcode manage signing automatically.

You can also set it once in `project.yml` under `settings.base.DEVELOPMENT_TEAM`
and re-run `xcodegen generate`.

## 3. Capabilities — App Group (required for the Share Extension)

The app and the Share Extension exchange data through an **App Group**. The id
lives in three places that **must all match**:

- `Shared/Config/AppConfig.swift` → `appGroupID = "group.com.jobtrack.shared"`
- `JobTrack/Resources/JobTrack.entitlements`
- `ShareExtension/ShareExtension.entitlements`

In Xcode, for **both** targets: **Signing & Capabilities → + Capability →
App Groups**, then tick (or add) `group.com.jobtrack.shared`. If you change the
id, update all three locations.

## 4. Capabilities — Keychain Sharing (for the API key)

The Anthropic API key is stored in the **Keychain**. To let both targets read it,
enable **Keychain Sharing** on both and use the group `com.jobtrack.shared`
(Xcode prefixes it with your Team id automatically; the entitlements use the
`$(AppIdentifierPrefix)` wildcard). If you only ever read the key from the main
app, Keychain Sharing is optional — the current Share Extension does not need it.

## 5. Where to paste your Anthropic API key

**You do not put the key in code or `Info.plist`.** Run the app and go to:

**Réglages (Settings) tab → Clé API → paste your key → “Enregistrer la clé”.**

- Get a key at <https://console.anthropic.com>.
- It is written to the Keychain (`KeychainService`), never to `UserDefaults`.
- Tap **“Tester la clé”** to verify connectivity/validity.

The Claude model is `claude-sonnet-4-6`, set in `AppConfig.claudeModel` — change
it there to switch models globally.

## 6. Run

- **iOS**: pick an iOS 17+ simulator or device, Run.
- **macOS**: pick *My Mac*, Run. (Uses the same SwiftUI code; `Settings` scene
  provides the macOS preferences window.)

## 7. Test

```bash
# from Xcode: ⌘U, or:
xcodebuild test -scheme JobTrack -destination 'platform=iOS Simulator,name=iPhone 15'
```

The `JobTrackTests` target covers the offer-list filtering/sorting logic and the
add-offer flow (with a mocked `ClaudeService`), demonstrating the service layer
is fully isolated and injectable.

---

## Using the app

1. **Add a CV** — *CV* tab → import a PDF. Text is extracted with PDFKit and used
   as context for letters and match scoring. Store several versions; one is the
   default.
2. **Add an offer** — *Offres* tab → **+**:
   - Paste the raw offer text → **Analyser avec Claude** (extracts
     title/company/location/description) → review/edit → **Enregistrer**.
   - Or copy a **screenshot**, then **OCR depuis le presse-papiers** (Vision).
   - Or use the **Share Extension** (below).
3. **Generate a cover letter** — open an offer → **Générer une lettre**, choose
   tone + length, edit, **régénérer**, then **copier** or **exporter en PDF**.
4. **Organize** — filter by status/company/tag, search, sort by date or
   pertinence (Claude match score).

## Using the Share Extension

From **Safari** or the **LinkedIn app**, tap **Share → JobTrack**. The extension
captures the shared URL/text into the App Group inbox; JobTrack imports it on next
launch/foreground and flags it **“à analyser”** so you can parse it with Claude.

> **macOS note.** The Share Extension is implemented with UIKit
> (`ShareViewController`), which targets iOS/Mac Catalyst. A native macOS share
> extension uses `NSExtension` with an `NSViewController` subclass; if you need
> the macOS share sheet, add a macOS-specific principal class. The paste/OCR
> import paths work on macOS today without any extension.

## Privacy / LinkedIn

JobTrack never automates reading your LinkedIn feed (no scraping, no headless
browser). All offer capture is manual: share, paste, or screenshot + OCR.
