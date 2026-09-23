using System;

namespace ActivityTracker.Core.Models;

/// <summary>
/// One continuous stretch of time spent in a single frontmost app (or idle).
/// Mirrors the schema of the macOS app's app_intervals table for consistency,
/// though the two are entirely separate local databases, never synced.
/// </summary>
public class AppInterval
{
    public long? Id { get; set; }
    public required string AppName { get; set; }
    public string? WindowTitle { get; set; }
    public string? Url { get; set; }
    public string? Domain { get; set; }
    public required DateTime StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public bool IsIdle { get; set; }
}

/// <summary>One minute-bucket of input-event-derived activity score (0-100).</summary>
public class ActivityScore
{
    public long? Id { get; set; }
    public required DateTime MinuteTimestamp { get; set; }
    public required int EventCount { get; set; }
    public required int Score { get; set; }
    public long? AppIntervalId { get; set; }
}

/// <summary>One captured screenshot (optional feature, off by default).</summary>
public class Screenshot
{
    public long? Id { get; set; }
    public required DateTime Timestamp { get; set; }
    public required string FilePath { get; set; }
    public int? ActivityScoreValue { get; set; }
    public long? AppIntervalId { get; set; }
}

/// <summary>
/// A meeting session (e.g. a Teams call), tracked independently of — and able
/// to overlap with — whatever app is frontmost.
/// </summary>
public class MeetingSession
{
    public long? Id { get; set; }
    public required string AppName { get; set; }
    public required DateTime StartTime { get; set; }
    public DateTime? EndTime { get; set; }
}

/// <summary>Aggregated time-per-app, used by the dashboard.</summary>
public record AppTimeSummary(string AppName, TimeSpan TotalTime);

/// <summary>Aggregated time-per-domain, used by the dashboard.</summary>
public record DomainTimeSummary(string Domain, TimeSpan TotalTime);
