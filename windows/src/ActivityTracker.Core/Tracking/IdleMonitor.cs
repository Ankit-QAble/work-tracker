using System;
using System.Threading;
using ActivityTracker.Core.Database;

namespace ActivityTracker.Core.Tracking;

/// <summary>
/// Polls system-wide idle time via GetLastInputInfo and fires a callback when
/// crossing the idle threshold in either direction — the Windows equivalent of
/// the macOS app's IdleMonitor (which uses CGEventSourceSecondsSinceLastEventType).
/// No polling of keystrokes/content — just "how long since the last input event".
/// </summary>
public sealed class IdleMonitor
{
    private readonly Func<double> _thresholdSecondsProvider;
    private readonly Action<bool> _onIdleChanged; // isIdle
    private Timer? _timer;
    private bool _isIdle;

    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(2);

    public IdleMonitor(Func<double> thresholdSecondsProvider, Action<bool> onIdleChanged)
    {
        _thresholdSecondsProvider = thresholdSecondsProvider;
        _onIdleChanged = onIdleChanged;
    }

    public void Start()
    {
        if (!OperatingSystem.IsWindows())
        {
            Log.Info("IdleMonitor: not running on Windows, skipping");
            return;
        }
        if (_timer != null) return;
        _timer = new Timer(_ => Tick(), null, PollInterval, PollInterval);
        Log.Info($"IdleMonitor started (threshold {_thresholdSecondsProvider()}s)");
    }

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
    }

    /// <summary>
    /// Raw idle seconds as reported by the OS — exposed so a supplementary
    /// signal (e.g. the activity-score tracker's own last-event timestamp) can
    /// be combined with it the same way the macOS port ended up needing to,
    /// in case a similar environment-specific discrepancy ever shows up here.
    /// </summary>
    public static double SecondsSinceLastInput()
    {
        if (!OperatingSystem.IsWindows()) return 0;

        var info = new Win32.LASTINPUTINFO();
        info.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(info);
        if (!Win32.GetLastInputInfo(ref info)) return 0;

        var idleTicks = (uint)Environment.TickCount - info.dwTime;
        return idleTicks / 1000.0;
    }

    private void Tick()
    {
        var idleSeconds = SecondsSinceLastInput();
        var threshold = _thresholdSecondsProvider();
        var nowIdle = idleSeconds >= threshold;

        if (nowIdle != _isIdle)
        {
            _isIdle = nowIdle;
            Log.Info(nowIdle ? $"Went idle after {(int)idleSeconds}s" : "Resumed from idle");
            _onIdleChanged(nowIdle);
        }
    }
}
