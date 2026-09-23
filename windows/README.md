# ActivityTracker for Windows

A native Windows port of the [macOS ActivityTracker](../README.md) — same
concept (local-only, single-user activity tracking, no cloud, no accounts),
completely separate codebase. **This is a first beta, built without access to
a real Windows machine to test on.** The database layer is genuinely verified
(it runs and was tested on macOS too, since `Microsoft.Data.Sqlite` is
cross-platform); everything that touches actual Windows APIs (the four
trackers below) compiles and cross-publishes cleanly but has **not been run on
real Windows yet**. It needs your help to find out what's broken.

## What's implemented

| Feature | Status |
|---|---|
| Active app tracking (foreground window via `SetWinEventHook`) | Implemented, unverified on real Windows |
| Idle detection (`GetLastInputInfo`) | Implemented, unverified on real Windows |
| Activity score (low-level keyboard/mouse hooks) | Implemented, unverified on real Windows — see the antivirus note below |
| Teams meeting detection | Implemented with an **unconfirmed heuristic** — see below |
| Dashboard (stat tiles, time-per-app breakdown) | Implemented, no visual timeline/chart yet |
| CSV export (day/week/month) | Implemented |
| Idle-resume prompt | Implemented |
| Settings (idle threshold, excluded apps) | Implemented |
| Chrome tab/domain tracking | **Not implemented yet** — needs UI Automation (a heavier, Windows-Desktop-only dependency); Chrome itself still gets tracked like any other app, just without the per-domain breakdown |
| Screenshots | Not implemented (wasn't in this version's scope) |
| Visual timeline bar | Not implemented (dashboard currently shows the app-time list only) |

## Running it

Prebuilt: grab the latest `.exe` from
[Releases](https://github.com/Ankit-QAble/work-tracker/releases) — it's
self-contained (no .NET install required), just run it. A tray icon should
appear near the clock.

From source: needs the [.NET SDK](https://dotnet.microsoft.com/download) (8+).
```powershell
cd windows
dotnet run --project src/ActivityTracker.App
```

Data lives under `%LOCALAPPDATA%\ActivityTracker\` (a `settings.json`, an
`activity.sqlite`, and `app.log`).

## What I need from you

This app was built and cross-compiled entirely from macOS — I have no way to
run or watch a Windows GUI, so the pieces above marked "unverified" are my
best-effort translation of the macOS logic into the Windows-equivalent APIs,
not something I've actually seen work. Please:

1. **Just run it for a normal day** and check the Dashboard shows sensible
   app-switch/idle data. If the tray icon doesn't appear, or the app crashes,
   check `%LOCALAPPDATA%\ActivityTracker\app.log` and share it.
2. **Join a real Teams meeting** and check whether it shows up as "Meeting
   Time" on the Dashboard afterward. The detection logs every window title
   Teams has open, every 10 seconds, to `app.log` — if meeting detection
   doesn't work, that log is exactly what's needed to fix the heuristic (see
   `MeetingDetector.cs` for the full reasoning; the short version: it assumes
   Teams-for-Windows opens a second window during a call, the same way
   Teams-for-Mac does, but that's an assumption).
3. **If your organization's antivirus/EDR software flags or blocks this app**,
   it's almost certainly the keyboard/mouse hook behind the activity score
   (`WH_KEYBOARD_LL`/`WH_MOUSE_LL`) — that's the same low-level mechanism a
   keylogger would use, even though this one only counts events and never
   reads their content. Worth checking with IT before relying on this at work
   if that's a concern.

## Architecture

```
windows/
  ActivityTrackerWindows.sln
  src/
    ActivityTracker.Core/     # DB layer, models, all tracking logic — plain
                               # net10.0, no Windows-only dependencies, so this
                               # half is actually testable/runnable on macOS too
      Database/
      Models/
      Tracking/                # Win32 P/Invoke trackers, each guarded by
                                # OperatingSystem.IsWindows() so the whole app
                                # still runs (harmlessly inert) on macOS
    ActivityTracker.App/       # Avalonia UI — tray icon, dashboard, settings
      Views/
      ViewModels/
```

Avalonia (not WPF) was a deliberate choice: WPF cannot be built or previewed
outside Windows at all, whereas Avalonia's UI actually runs on macOS too — the
Dashboard/Settings windows and tray icon were visually built and smoke-tested
here, on macOS, before ever touching Windows. Only the Win32-specific tracking
code (foreground window hooks, idle detection, keyboard/mouse hooks, Teams
window enumeration) is genuinely unverified, since P/Invoke calls to
`user32.dll` etc. only resolve at runtime on actual Windows.

## Building a release

```bash
dotnet publish src/ActivityTracker.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o dist/win-x64
```

Produces a single `ActivityTracker.App.exe` (~85MB, self-contained — no .NET
install required on the target machine). This can be cross-compiled from
macOS or Linux; it does not need to run on Windows to be *built* for Windows.
