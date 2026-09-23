using System;
using System.Threading;
using ActivityTracker.Core.Database;

namespace ActivityTracker.Core.Tracking;

/// <summary>
/// Listens for keyboard/mouse *events* via low-level Win32 hooks
/// (WH_KEYBOARD_LL / WH_MOUSE_LL) and turns them into a 0-100 "activity score"
/// per 60-second window — the Windows equivalent of the macOS app's
/// ActivityScoreTracker (which uses a CGEventTap). Only event counts are ever
/// touched — key codes, characters, and click targets are never read or stored.
///
/// Some corporate antivirus/EDR software flags low-level keyboard hooks as
/// suspicious (they're the same mechanism a real keylogger would use, even
/// though this one only increments a counter) — worth knowing if this gets
/// blocked or triggers a warning on a locked-down machine.
///
/// Requires a running Win32 message loop on the installing thread, same as
/// ForegroundAppTracker.
/// </summary>
public sealed class ActivityScoreTracker
{
    /// <summary>(minuteStart, eventCount, score)</summary>
    private readonly Action<DateTime, int, int> _onMinuteFinished;

    private IntPtr _keyboardHook = IntPtr.Zero;
    private IntPtr _mouseHook = IntPtr.Zero;
    private readonly Win32.LowLevelHookProc _keyboardProc;
    private readonly Win32.LowLevelHookProc _mouseProc;

    private int _eventCount;
    private DateTime _currentMinuteStart;
    private Timer? _minuteTimer;

    /// <summary>
    /// Timestamp of the most recent event seen — exposed the same way the
    /// macOS port ended up needing it, as a fallback idle signal in case
    /// GetLastInputInfo ever shows a similar discrepancy from real input as
    /// CGEventSource did on macOS (see IdleMonitor.SecondsSinceLastInput).
    /// </summary>
    public DateTime LastEventAt { get; private set; } = DateTime.Now;

    /// <summary>Events/minute considered "fully active" (100) — a ceiling, not an average.</summary>
    private const int MaxEventsPerMinuteForFullScore = 600;

    public ActivityScoreTracker(Action<DateTime, int, int> onMinuteFinished)
    {
        _onMinuteFinished = onMinuteFinished;
        _currentMinuteStart = FlooredToMinute(DateTime.Now);
        _keyboardProc = KeyboardHookCallback;
        _mouseProc = MouseHookCallback;
    }

    public void Start()
    {
        if (!OperatingSystem.IsWindows())
        {
            Log.Info("ActivityScoreTracker: not running on Windows, skipping");
            return;
        }
        if (_keyboardHook != IntPtr.Zero) return;

        var hModule = Win32.GetModuleHandle(null);
        _keyboardHook = Win32.SetWindowsHookEx(Win32.WH_KEYBOARD_LL, _keyboardProc, hModule, 0);
        _mouseHook = Win32.SetWindowsHookEx(Win32.WH_MOUSE_LL, _mouseProc, hModule, 0);

        if (_keyboardHook == IntPtr.Zero || _mouseHook == IntPtr.Zero)
        {
            Log.Error("ActivityScoreTracker: SetWindowsHookEx failed — activity score will stay at 0");
        }

        StartMinuteTimer();
        Log.Info("ActivityScoreTracker started");
    }

    public void Stop()
    {
        if (_keyboardHook != IntPtr.Zero) { Win32.UnhookWindowsHookEx(_keyboardHook); _keyboardHook = IntPtr.Zero; }
        if (_mouseHook != IntPtr.Zero) { Win32.UnhookWindowsHookEx(_mouseHook); _mouseHook = IntPtr.Zero; }
        _minuteTimer?.Dispose();
        _minuteTimer = null;
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            _eventCount++;
            LastEventAt = DateTime.Now;
        }
        return Win32.CallNextHookEx(_keyboardHook, nCode, wParam, lParam);
    }

    private IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            _eventCount++;
            LastEventAt = DateTime.Now;
        }
        return Win32.CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private void StartMinuteTimer()
    {
        var now = DateTime.Now;
        var nextMinute = FlooredToMinute(now).AddMinutes(1);
        var initialDelay = nextMinute - now;
        _minuteTimer = new Timer(_ => FinishMinute(), null, initialDelay, TimeSpan.FromMinutes(1));
    }

    private void FinishMinute()
    {
        var count = Interlocked.Exchange(ref _eventCount, 0);
        var score = Normalize(count);
        var minute = _currentMinuteStart;
        _currentMinuteStart = FlooredToMinute(DateTime.Now);
        _onMinuteFinished(minute, count, score);
    }

    private static int Normalize(int eventCount)
    {
        var ratio = (double)eventCount / MaxEventsPerMinuteForFullScore;
        return Math.Clamp((int)Math.Round(ratio * 100), 0, 100);
    }

    private static DateTime FlooredToMinute(DateTime dt) => new(dt.Year, dt.Month, dt.Day, dt.Hour, dt.Minute, 0, dt.Kind);
}
