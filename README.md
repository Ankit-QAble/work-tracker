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

## Running this on your own Mac

### Preconditions

- **macOS 14 (Sonoma) or later.**
- **Xcode Command Line Tools** (a full Xcode.app install is *not* required).
  Check with:
  ```bash
  xcode-select -p
  ```
  If that errors instead of printing a path, install them with:
  ```bash
  xcode-select --install
  ```
- **Internet access** the first time you build — Swift Package Manager needs
  to fetch the GRDB.swift dependency from GitHub. Every build after that works
  fine offline.
- **Git**, to clone the repo (comes with the Command Line Tools above).

### Setup

```bash
git clone https://github.com/Ankit-QAble/work-tracker.git
cd work-tracker
./Scripts/build_app.sh debug
open ~/Applications/ActivityTracker.app
```

What that does:

1. `swift build` compiles the executable (first run also downloads GRDB.swift —
   takes a minute or two; later runs are fast).
2. The script assembles a proper `.app` bundle (`Info.plist`, `LSUIElement`)
   around the compiled binary.
3. **First run only on a given Mac**: it generates a local, self-signed code
   -signing certificate and trusts it in your login keychain, so that macOS
   permission grants (see below) survive future rebuilds instead of resetting
   every time. This is fully automatic, scoped to your own login keychain, and
   never requires `sudo` or your password. See *"A note on code signing & TCC
   permissions"* below for exactly what it does and why.
4. It installs the built app to `~/Applications/ActivityTracker.app` and
   prints the `open` command to launch it.

After that first launch, look for a colored dot in your menu bar (near the
clock) — that's the app. Click it for Pause/Resume, Dashboard, and Settings.

### After first launch: grant permissions

The app works without any of these, but each feature it's missing will log a
one-line notice instead of crashing. Grant what you want to use — see the
**Permissions** table below for what each one enables, and use
**Settings → Permissions** in the app for a direct link to the right System
Settings pane.

A couple of things worth knowing up front, since they're easy to lose time to:

- **Accessibility prompts automatically** the first time the app needs it;
  the others (Input Monitoring, Automation, Screen Recording) don't — you
  need to open System Settings and add the app yourself for those.
- **Quit and relaunch the app after granting a permission.** macOS checks most
  of these once per process launch, so a permission granted while the app is
  already running often won't take effect until you restart it.

### Rebuilding after pulling changes

```bash
./Scripts/build_app.sh debug     # or `release` for an optimized build
```
Quit any running copy first (menu bar → Quit) so `open` launches the fresh
build rather than reusing the old process.

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
(`ActivityTrackerLocalSigning`) **and** pins the designated requirement
explicitly to that certificate:

```
designated => identifier "com.ankit.activitytracker" and certificate leaf = H"<cert-sha1>"
```

With that in place, permission grants survive rebuilds.

**This is fully automatic.** The first time `Scripts/build_app.sh` runs on a
given Mac and doesn't find `ActivityTrackerLocalSigning` in the keychain, it
generates a self-signed code-signing certificate and trusts it — scoped to
your own login keychain, no `sudo`, no password prompt. Every build after that
reuses the same identity. If you ever want to do this by hand (or see exactly
what the script does), it's equivalent to:

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

If this identity is somehow missing or unavailable at build time, the script
falls back to ad-hoc signing (with the rebuild caveat described above).

## Non-goals

No cloud sync, no accounts, no multi-user support, no keystroke content
logging (event counts only), no App Store distribution.
