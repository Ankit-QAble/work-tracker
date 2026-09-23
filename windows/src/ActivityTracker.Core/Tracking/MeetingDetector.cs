using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading;
using ActivityTracker.Core.Database;

namespace ActivityTracker.Core.Tracking;

/// <summary>
/// Detects an in-progress Microsoft Teams meeting, independent of whether
/// Teams is the foreground app — the Windows port of the macOS app's
/// MeetingDetector. Logs to meeting_sessions, a separate table from
/// app_intervals specifically because it's allowed to overlap (a call can run
/// in the background while a different app is the one actually tracked).
///
/// UNVERIFIED HEURISTIC — this is the one piece of this port I could not
/// validate myself (no Windows machine here). The macOS version's working
/// heuristic came from watching real Teams windows across three states (not
/// in a meeting / channel meeting / 1:1 call) and finding a structural pattern:
/// every meeting state opened a second window distinct from the normal single
/// "Chat | ..." browsing window — NOT from guessing at title wording, which
/// varied a lot between meeting types. This port assumes the same structural
/// pattern likely holds on the Windows Teams client (it's the same app,
/// probably similar window architecture), but that's an assumption, not a
/// confirmed fact — Teams' Windows and macOS clients aren't guaranteed to
/// behave identically. IsLikelyInMeeting logs full window counts/titles every
/// poll specifically so this can be validated/corrected the same way the
/// macOS heuristic was: watch the real log during an actual call and adjust
/// LooksLikeMeeting from what it actually shows.
/// </summary>
public sealed class MeetingDetector
{
    private static readonly string[] TeamsProcessNames = ["ms-teams", "Teams"];
    private const string DisplayName = "Microsoft Teams";

    private Timer? _timer;
    private bool _inMeeting;
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(10);

    public void Start()
    {
        if (!OperatingSystem.IsWindows())
        {
            Log.Info("MeetingDetector: not running on Windows, skipping");
            return;
        }
        if (_timer != null) return;
        _timer = new Timer(_ => Poll(), null, TimeSpan.FromSeconds(3), PollInterval);
        Log.Info("MeetingDetector started");
    }

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
    }

    private void Poll()
    {
        Process[]? teamsProcesses = null;
        foreach (var name in TeamsProcessNames)
        {
            var found = Process.GetProcessesByName(name);
            if (found.Length > 0) { teamsProcesses = found; break; }
        }

        if (teamsProcesses is null || teamsProcesses.Length == 0)
        {
            if (_inMeeting)
            {
                _inMeeting = false;
                ActivityStore.Shared.EndOpenMeetingSession(DisplayName);
                Log.Info("Meeting ended (Teams not running)");
            }
            return;
        }

        var pids = new HashSet<int>();
        foreach (var p in teamsProcesses) pids.Add(p.Id);

        var titles = EnumerateVisibleWindowTitles(pids);
        // Diagnostic logging every poll — see the class doc. This is the data
        // that needs collecting from a real call to confirm or correct the
        // heuristic below.
        Log.Info($"MeetingDetector: Teams has {titles.Count} visible window(s): [{string.Join(" | ", titles)}]");

        var nowInMeeting = LooksLikeMeeting(titles);
        if (nowInMeeting && !_inMeeting)
        {
            _inMeeting = true;
            ActivityStore.Shared.StartMeetingSessionIfNeeded(DisplayName);
            Log.Info("Meeting detected: Microsoft Teams");
        }
        else if (!nowInMeeting && _inMeeting)
        {
            _inMeeting = false;
            ActivityStore.Shared.EndOpenMeetingSession(DisplayName);
            Log.Info("Meeting ended: Microsoft Teams");
        }
    }

    /// <summary>
    /// Same structural principle as the macOS version: 2+ windows, at least
    /// one not looking like the normal single chat-browsing view, is treated
    /// as a meeting. "Chat" is a guess at what a normal Teams-for-Windows
    /// browsing window's title looks like — unconfirmed; check the diagnostic
    /// log from a real call and adjust this if it doesn't match reality.
    /// </summary>
    public static bool LooksLikeMeeting(IReadOnlyList<string> windowTitles)
    {
        if (windowTitles.Count < 2) return false;
        foreach (var title in windowTitles)
        {
            if (!title.Contains("Chat", StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    private static List<string> EnumerateVisibleWindowTitles(HashSet<int> pids)
    {
        var titles = new List<string>();
        Win32.EnumWindows((hWnd, _) =>
        {
            if (!Win32.IsWindowVisible(hWnd)) return true;
            Win32.GetWindowThreadProcessId(hWnd, out var pid);
            if (!pids.Contains((int)pid)) return true;

            var sb = new StringBuilder(512);
            var length = Win32.GetWindowText(hWnd, sb, sb.Capacity);
            if (length > 0) titles.Add(sb.ToString());
            return true;
        }, IntPtr.Zero);
        return titles;
    }
}
