# ActivityTracker

A native macOS menu bar app for personal, single-user activity tracking (à la
Hubstaff/RescueTime), running entirely locally — no cloud backend, no accounts,
no networking. All data lives on disk under
`~/Library/Application Support/ActivityTracker/`.

## Features

- Active app tracking via `NSWorkspace` app-switch notifications
- Chrome tab URL/title polling via AppleScript (Automation permission)
- Window-title polling for any other app via the Accessibility API
- Idle detection (auto-pauses tracking after a configurable threshold, logs the
  idle gap as its own interval type)
- A 0–100 per-minute "activity score" from a `CGEventTap` — counts input events
  only, never key content
- Optional periodic screenshots (off by default) via ScreenCaptureKit
- A SwiftUI dashboard: timeline, time-per-app/domain breakdown, activity score
  chart, screenshot strip
- CSV export (day/week/month) for spreadsheet analysis
- Menu bar controls: pause/resume, open dashboard, settings, quit

## Tech stack

- Swift + SwiftUI/AppKit, macOS 14+
- SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
- Built with Swift Package Manager — **no Xcode.app required** (Command Line
  Tools are enough), since the app is assembled into a `.app` bundle by hand.

## Building & running

```bash
./Scripts/build_app.sh debug     # or `release` for an optimized build
open ~/Applications/ActivityTracker.app
```

The build script compiles with `swift build`, assembles a proper `.app` bundle
(`Info.plist`, `LSUIElement`), code-signs it, and installs a copy to
`~/Applications/ActivityTracker.app`.

## Permissions

The app needs, and gracefully degrades without, four permissions:

| Permission | Used for |
|---|---|
| Accessibility | Window titles for non-browser apps |
| Automation (Google Chrome) | Browser tab URL/title |
| Input Monitoring | The per-minute activity score |
| Screen Recording | Optional periodic screenshots |

Grant these in **System Settings → Privacy & Security**. If a feature isn't
tracking, check there first (Settings → Permissions tab in the app links
straight to it).

## A note on code signing & TCC permissions

This app is **not notarized** (no paid Apple Developer account involved) — it's
signed with a locally-generated, self-signed certificate for personal use only.

This matters because of how macOS ties permission grants (Accessibility, Input
Monitoring, etc.) to a specific code signature:

- **Ad-hoc signing** (`codesign --sign -`) derives its designated requirement
  from the binary's content hash (`cdhash`). Every rebuild changes that hash,
  which silently invalidates every previously-granted permission — extremely
  disruptive during iterative development.
- **A bare self-signed certificate** (no trust chain) has the same problem by
  default: `codesign` still falls back to a `cdhash`-based requirement unless
  told otherwise.

The fix used here: `Scripts/build_app.sh` signs with a local certificate
(`ActivityTrackerLocalSigning`, created once and stored in the login keychain)
**and** pins the designated requirement explicitly to that certificate:

```
designated => identifier "com.ankit.activitytracker" and certificate leaf = H"<cert-sha1>"
```

With that in place, permission grants survive rebuilds. If this local signing
identity doesn't exist on a given machine, the script falls back to ad-hoc
signing (with the rebuild caveat above).

To (re)create the signing identity on a new machine:

```bash
# One-time: generate a self-signed code-signing cert and trust it for that purpose.
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=ActivityTrackerLocalSigning" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -out cert.p12 -inkey key.pem -in cert.pem -passout pass:temp -name "ActivityTrackerLocalSigning"
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P temp -A -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -d -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm key.pem cert.p12  # cert.pem can stay; the private key/p12 no longer need to exist on disk
```

## Non-goals

No cloud sync, no accounts, no multi-user support, no keystroke content
logging (event counts only), no App Store distribution.
