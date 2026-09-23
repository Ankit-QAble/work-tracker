using System;
using System.Diagnostics;
using System.Text;
using ActivityTracker.Core.Database;

namespace ActivityTracker.Core.Tracking;

/// <summary>
/// Tracks the foreground (frontmost) window via a WinEventHook on
/// EVENT_SYSTEM_FOREGROUND — the Windows equivalent of the macOS app's
/// AppSwitchObserver (which uses NSWorkspace.didActivateApplicationNotification).
/// Every foreground change fires once, with whichever app just became active.
///
/// Requires a running Win32 message loop on the thread that calls Start() —
/// SetWinEventHook delivers callbacks through the message queue. Avalonia's UI
/// thread already runs one on Windows, so this must be started from there.
/// </summary>
public sealed class ForegroundAppTracker
{
    private readonly Action<string, string?> _onActivate; // (appName, windowTitle)
    private IntPtr _hook = IntPtr.Zero;
    // Keep a strong reference — SetWinEventHook only stores an unmanaged
    // function pointer; if the delegate is garbage collected, native code
    // ends up calling into freed memory.
    private readonly Win32.WinEventDelegate _delegate;

    public ForegroundAppTracker(Action<string, string?> onActivate)
    {
        _onActivate = onActivate;
        _delegate = OnWinEvent;
    }

    public void Start()
    {
        if (!OperatingSystem.IsWindows())
        {
            Log.Info("ForegroundAppTracker: not running on Windows, skipping");
            return;
        }
        if (_hook != IntPtr.Zero) return;

        _hook = Win32.SetWinEventHook(
            Win32.EVENT_SYSTEM_FOREGROUND, Win32.EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, _delegate, 0, 0, Win32.WINEVENT_OUTOFCONTEXT);

        if (_hook == IntPtr.Zero)
        {
            Log.Error("ForegroundAppTracker: SetWinEventHook failed");
            return;
        }

        Log.Info("ForegroundAppTracker started");
        ReportCurrentForeground();
    }

    /// <summary>
    /// Re-queries and reports whatever's frontmost right now — used both at
    /// Start() and whenever the coordinator resumes from idle/pause, mirroring
    /// how the macOS port re-reads NSWorkspace.frontmostApplication at those
    /// same points rather than waiting for the next natural switch event.
    /// </summary>
    public void ReportCurrentForeground()
    {
        if (!OperatingSystem.IsWindows()) return;
        ReportForeground(Win32.GetForegroundWindow());
    }

    public void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            Win32.UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        ReportForeground(hwnd);
    }

    private void ReportForeground(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;

        Win32.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return;

        string appName;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            // MainModule access can throw for elevated/system processes this
            // process doesn't have rights to inspect — fall back to the bare
            // process name rather than losing the whole tracking tick over it.
            appName = TryGetFriendlyName(process) ?? process.ProcessName;
        }
        catch (Exception ex)
        {
            Log.Error($"ForegroundAppTracker: couldn't resolve process {pid}: {ex.Message}");
            return;
        }

        var title = GetWindowTitle(hwnd);
        _onActivate(appName, title);
    }

    private static string? TryGetFriendlyName(Process process)
    {
        try
        {
            var description = process.MainModule?.FileVersionInfo.FileDescription;
            return string.IsNullOrWhiteSpace(description) ? null : description;
        }
        catch
        {
            return null;
        }
    }

    private static string? GetWindowTitle(IntPtr hwnd)
    {
        var sb = new StringBuilder(512);
        var length = Win32.GetWindowText(hwnd, sb, sb.Capacity);
        return length > 0 ? sb.ToString() : null;
    }
}
