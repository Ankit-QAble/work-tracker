using System;
using ActivityTracker.Core.Database;
using ActivityTracker.Core.Models;

namespace ActivityTracker.Core.Tracking;

public enum TrackingStatus { Tracking, Idle, Paused }

/// <summary>
/// Central brain: owns the current tracking state, wires together the
/// individual trackers, and is the single place that decides "what app
/// interval is open right now" — the Windows port of the macOS app's
/// TrackingCoordinator. Must be started from the UI thread (the trackers rely
/// on a running Win32 message loop for their hooks).
/// </summary>
public sealed class TrackingCoordinator
{
    private static readonly Lazy<TrackingCoordinator> _shared = new(() => new TrackingCoordinator());
    public static TrackingCoordinator Shared => _shared.Value;

    public event Action<TrackingStatus>? StatusChanged;
    public TrackingStatus Status { get; private set; } = TrackingStatus.Tracking;
    public string CurrentAppName { get; private set; } = "—";

    /// <summary>
    /// Fired when returning from an idle stretch longer than
    /// IdlePromptThresholdSeconds — the UI layer shows a popup asking whether
    /// to keep the idle time as work, and calls the supplied action if so.
    /// </summary>
    public Action<TimeSpan, string, Action>? IdleResumePromptRequested;

    private readonly ActivityStore _store = ActivityStore.Shared;
    private readonly AppSettings _settings = AppSettings.Shared;

    private readonly ForegroundAppTracker _appTracker;
    private readonly IdleMonitor _idleMonitor;
    private readonly ActivityScoreTracker _activityScoreTracker;
    private readonly MeetingDetector _meetingDetector;

    private long? _currentIntervalId;
    private bool _isManuallyPaused;

    private DateTime? _idleStartDate;
    private long? _idleIntervalId;
    private string? _appNameBeforeIdle;

    private TrackingCoordinator()
    {
        _appTracker = new ForegroundAppTracker(HandleAppActivated);
        _idleMonitor = new IdleMonitor(() => _settings.IdleThresholdSeconds, HandleIdleChanged);
        _activityScoreTracker = new ActivityScoreTracker((minute, count, score) =>
            _store.RecordActivityScore(minute, count, score, _currentIntervalId));
        _meetingDetector = new MeetingDetector();
    }

    public void Start()
    {
        _appTracker.Start();
        _idleMonitor.Start();
        _activityScoreTracker.Start();
        _meetingDetector.Start();
    }

    public void TogglePause()
    {
        _isManuallyPaused = !_isManuallyPaused;
        if (_isManuallyPaused)
        {
            SetStatus(TrackingStatus.Paused);
            // Close whatever was open and log nothing further — pausing is a
            // deliberate choice, not something to measure (unlike idle, which
            // the app detects on its own and does log as its own category).
            _store.CloseCurrentInterval();
            _currentIntervalId = null;
            // Drop any in-flight idle bookkeeping — see the equivalent comment
            // in the macOS TrackingCoordinator for why this matters.
            _idleStartDate = null;
            _idleIntervalId = null;
            _appNameBeforeIdle = null;
        }
        else
        {
            SetStatus(TrackingStatus.Tracking);
            _appTracker.ReportCurrentForeground();
        }
    }

    private void HandleAppActivated(string appName, string? windowTitle)
    {
        if (_isManuallyPaused) return;
        if (Status == TrackingStatus.Idle) return; // resumed by HandleIdleChanged instead

        CurrentAppName = appName;

        if (_settings.IsExcluded(appName))
        {
            _store.CloseCurrentInterval();
            _currentIntervalId = null;
            return;
        }

        _currentIntervalId = _store.StartInterval(appName, windowTitle, null, null, false);
    }

    private void HandleIdleChanged(bool isIdle)
    {
        if (_isManuallyPaused) return;

        if (isIdle)
        {
            SetStatus(TrackingStatus.Idle);
            _appNameBeforeIdle = (CurrentAppName != "—" && _currentIntervalId != null) ? CurrentAppName : null;
            _idleStartDate = DateTime.Now;
            _currentIntervalId = _store.StartInterval("Idle", null, null, null, true);
            _idleIntervalId = _currentIntervalId;
        }
        else
        {
            var idleDuration = _idleStartDate.HasValue ? DateTime.Now - _idleStartDate.Value : TimeSpan.Zero;
            var intervalToReattribute = _idleIntervalId;
            var previousApp = _appNameBeforeIdle;
            _idleStartDate = null;
            _idleIntervalId = null;
            _appNameBeforeIdle = null;

            SetStatus(TrackingStatus.Tracking);
            _appTracker.ReportCurrentForeground();

            if (_settings.IdlePromptEnabled
                && idleDuration.TotalSeconds >= _settings.IdlePromptThresholdSeconds
                && intervalToReattribute.HasValue && previousApp != null)
            {
                IdleResumePromptRequested?.Invoke(idleDuration, previousApp, () =>
                {
                    Log.Info($"Idle stretch ({(int)idleDuration.TotalSeconds}s) reattributed to {previousApp}");
                    _store.ReattributeAsTracked(intervalToReattribute.Value, previousApp);
                });
            }
        }
    }

    public void Shutdown()
    {
        _store.CloseCurrentInterval();
        _appTracker.Stop();
        _idleMonitor.Stop();
        _activityScoreTracker.Stop();
        _meetingDetector.Stop();
        _store.CloseAllOpenMeetingSessions();
    }

    private void SetStatus(TrackingStatus status)
    {
        Status = status;
        StatusChanged?.Invoke(status);
    }
}
