using System;
using System.Collections.Generic;
using System.Globalization;
using Microsoft.Data.Sqlite;
using ActivityTracker.Core.Models;

namespace ActivityTracker.Core.Database;

/// <summary>
/// Simple data-access layer sitting on top of DatabaseManager. All timestamps
/// are stored as UTC ISO-8601 strings and converted to/from local time at the
/// boundary — SQLite has no native datetime type, and comparing consistent UTC
/// strings avoids local-timezone ambiguity in the stored data itself.
/// </summary>
public sealed class ActivityStore
{
    private static readonly Lazy<ActivityStore> _shared = new(() => new ActivityStore());
    public static ActivityStore Shared => _shared.Value;

    private ActivityStore() { }

    private static string ToDb(DateTime dt) => dt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);
    private static DateTime FromDb(string s) => DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind).ToLocalTime();

    // MARK: - App intervals

    /// <summary>Closes any still-open interval (end_time IS NULL) and opens a new one.</summary>
    public long? StartInterval(string appName, string? windowTitle, string? url, string? domain, bool isIdle, DateTime? at = null)
    {
        var date = at ?? DateTime.Now;
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var tx = db.BeginTransaction();
            CloseOpenIntervals(db, date);

            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                INSERT INTO app_intervals (app_name, window_title, url, domain, start_time, is_idle)
                VALUES ($appName, $windowTitle, $url, $domain, $startTime, $isIdle);
                SELECT last_insert_rowid();
                """;
            cmd.Parameters.AddWithValue("$appName", appName);
            cmd.Parameters.AddWithValue("$windowTitle", (object?)windowTitle ?? DBNull.Value);
            cmd.Parameters.AddWithValue("$url", (object?)url ?? DBNull.Value);
            cmd.Parameters.AddWithValue("$domain", (object?)domain ?? DBNull.Value);
            cmd.Parameters.AddWithValue("$startTime", ToDb(date));
            cmd.Parameters.AddWithValue("$isIdle", isIdle ? 1 : 0);
            var id = (long)cmd.ExecuteScalar()!;
            tx.Commit();
            return id;
        }
        catch (Exception ex)
        {
            Log.Error($"StartInterval failed: {ex.Message}");
            return null;
        }
    }

    /// <summary>Closes whatever interval is currently open, without opening a new one.</summary>
    public void CloseCurrentInterval(DateTime? at = null)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            CloseOpenIntervals(db, at ?? DateTime.Now);
        }
        catch (Exception ex)
        {
            Log.Error($"CloseCurrentInterval failed: {ex.Message}");
        }
    }

    private static void CloseOpenIntervals(SqliteConnection db, DateTime at)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = "UPDATE app_intervals SET end_time = $endTime WHERE end_time IS NULL";
        cmd.Parameters.AddWithValue("$endTime", ToDb(at));
        cmd.ExecuteNonQuery();
    }

    /// <summary>
    /// Updates the window title/URL/domain of whatever interval is currently
    /// open, without closing it — used by browser/window-title pollers so a
    /// fast-changing tab/title doesn't fragment the app interval into dozens
    /// of tiny rows.
    /// </summary>
    public void UpdateOpenInterval(string? windowTitle = null, string? url = null, string? domain = null)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            var sets = new List<string>();
            if (windowTitle != null) sets.Add("window_title = $windowTitle");
            if (url != null) sets.Add("url = $url");
            if (domain != null) sets.Add("domain = $domain");
            if (sets.Count == 0) return;

            cmd.CommandText = $"UPDATE app_intervals SET {string.Join(", ", sets)} WHERE end_time IS NULL";
            if (windowTitle != null) cmd.Parameters.AddWithValue("$windowTitle", windowTitle);
            if (url != null) cmd.Parameters.AddWithValue("$url", url);
            if (domain != null) cmd.Parameters.AddWithValue("$domain", domain);
            cmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Log.Error($"UpdateOpenInterval failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Reattributes a previously-idle interval to a real app as tracked time —
    /// used when the idle-resume prompt's "keep as work" choice is made.
    /// </summary>
    public void ReattributeAsTracked(long intervalId, string appName)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = "UPDATE app_intervals SET is_idle = 0, app_name = $appName WHERE id = $id";
            cmd.Parameters.AddWithValue("$appName", appName);
            cmd.Parameters.AddWithValue("$id", intervalId);
            cmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Log.Error($"ReattributeAsTracked failed: {ex.Message}");
        }
    }

    public List<AppInterval> Intervals(DateTime start, DateTime end)
    {
        var result = new List<AppInterval>();
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                SELECT id, app_name, window_title, url, domain, start_time, end_time, is_idle
                FROM app_intervals
                WHERE start_time < $end AND (end_time IS NULL OR end_time > $start)
                ORDER BY start_time ASC
                """;
            cmd.Parameters.AddWithValue("$start", ToDb(start));
            cmd.Parameters.AddWithValue("$end", ToDb(end));
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add(new AppInterval
                {
                    Id = reader.GetInt64(0),
                    AppName = reader.GetString(1),
                    WindowTitle = reader.IsDBNull(2) ? null : reader.GetString(2),
                    Url = reader.IsDBNull(3) ? null : reader.GetString(3),
                    Domain = reader.IsDBNull(4) ? null : reader.GetString(4),
                    StartTime = FromDb(reader.GetString(5)),
                    EndTime = reader.IsDBNull(6) ? null : FromDb(reader.GetString(6)),
                    IsIdle = reader.GetInt32(7) != 0
                });
            }
        }
        catch (Exception ex)
        {
            Log.Error($"Intervals query failed: {ex.Message}");
        }
        return result;
    }

    public List<AppInterval> IntervalsOnDay(DateTime day)
    {
        var start = day.Date;
        return Intervals(start, start.AddDays(1));
    }

    public List<AppTimeSummary> AppTimeSummary(DateTime day)
    {
        var (start, end) = (day.Date, day.Date.AddDays(1));
        var totals = new Dictionary<string, TimeSpan>();
        foreach (var interval in IntervalsOnDay(day))
        {
            if (interval.IsIdle) continue;
            var clampedStart = interval.StartTime < start ? start : interval.StartTime;
            var clampedEnd = (interval.EndTime ?? DateTime.Now) > end ? end : (interval.EndTime ?? DateTime.Now);
            if (clampedEnd <= clampedStart) continue;
            totals[interval.AppName] = totals.GetValueOrDefault(interval.AppName) + (clampedEnd - clampedStart);
        }
        var list = new List<AppTimeSummary>();
        foreach (var kv in totals) list.Add(new AppTimeSummary(kv.Key, kv.Value));
        list.Sort((a, b) => b.TotalTime.CompareTo(a.TotalTime));
        return list;
    }

    public List<DomainTimeSummary> DomainTimeSummary(DateTime day)
    {
        var (start, end) = (day.Date, day.Date.AddDays(1));
        var totals = new Dictionary<string, TimeSpan>();
        foreach (var interval in IntervalsOnDay(day))
        {
            if (interval.IsIdle || string.IsNullOrEmpty(interval.Domain)) continue;
            var clampedStart = interval.StartTime < start ? start : interval.StartTime;
            var clampedEnd = (interval.EndTime ?? DateTime.Now) > end ? end : (interval.EndTime ?? DateTime.Now);
            if (clampedEnd <= clampedStart) continue;
            totals[interval.Domain] = totals.GetValueOrDefault(interval.Domain) + (clampedEnd - clampedStart);
        }
        var list = new List<DomainTimeSummary>();
        foreach (var kv in totals) list.Add(new DomainTimeSummary(kv.Key, kv.Value));
        list.Sort((a, b) => b.TotalTime.CompareTo(a.TotalTime));
        return list;
    }

    // MARK: - Activity scores

    public long? RecordActivityScore(DateTime minuteTimestamp, int eventCount, int score, long? appIntervalId)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                INSERT INTO activity_scores (minute_timestamp, event_count, score, app_interval_id)
                VALUES ($minute, $count, $score, $intervalId);
                SELECT last_insert_rowid();
                """;
            cmd.Parameters.AddWithValue("$minute", ToDb(minuteTimestamp));
            cmd.Parameters.AddWithValue("$count", eventCount);
            cmd.Parameters.AddWithValue("$score", score);
            cmd.Parameters.AddWithValue("$intervalId", (object?)appIntervalId ?? DBNull.Value);
            return (long)cmd.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            Log.Error($"RecordActivityScore failed: {ex.Message}");
            return null;
        }
    }

    public List<ActivityScore> ActivityScoresOnDay(DateTime day)
    {
        var (start, end) = (day.Date, day.Date.AddDays(1));
        var result = new List<ActivityScore>();
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                SELECT id, minute_timestamp, event_count, score, app_interval_id
                FROM activity_scores WHERE minute_timestamp >= $start AND minute_timestamp < $end
                ORDER BY minute_timestamp ASC
                """;
            cmd.Parameters.AddWithValue("$start", ToDb(start));
            cmd.Parameters.AddWithValue("$end", ToDb(end));
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add(new ActivityScore
                {
                    Id = reader.GetInt64(0),
                    MinuteTimestamp = FromDb(reader.GetString(1)),
                    EventCount = reader.GetInt32(2),
                    Score = reader.GetInt32(3),
                    AppIntervalId = reader.IsDBNull(4) ? null : reader.GetInt64(4)
                });
            }
        }
        catch (Exception ex)
        {
            Log.Error($"ActivityScoresOnDay failed: {ex.Message}");
        }
        return result;
    }

    public int? AverageActivityScore(DateTime start, DateTime end)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = "SELECT AVG(score) FROM activity_scores WHERE minute_timestamp >= $start AND minute_timestamp < $end";
            cmd.Parameters.AddWithValue("$start", ToDb(start));
            cmd.Parameters.AddWithValue("$end", ToDb(end));
            var result = cmd.ExecuteScalar();
            return result is DBNull or null ? null : (int)Math.Round(Convert.ToDouble(result));
        }
        catch (Exception ex)
        {
            Log.Error($"AverageActivityScore failed: {ex.Message}");
            return null;
        }
    }

    // MARK: - Meeting sessions

    public long? StartMeetingSessionIfNeeded(string appName, DateTime? at = null)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using (var check = db.CreateCommand())
            {
                check.CommandText = "SELECT id FROM meeting_sessions WHERE app_name = $appName AND end_time IS NULL";
                check.Parameters.AddWithValue("$appName", appName);
                var existing = check.ExecuteScalar();
                if (existing is long existingId) return existingId;
            }

            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                INSERT INTO meeting_sessions (app_name, start_time) VALUES ($appName, $start);
                SELECT last_insert_rowid();
                """;
            cmd.Parameters.AddWithValue("$appName", appName);
            cmd.Parameters.AddWithValue("$start", ToDb(at ?? DateTime.Now));
            return (long)cmd.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            Log.Error($"StartMeetingSessionIfNeeded failed: {ex.Message}");
            return null;
        }
    }

    public void EndOpenMeetingSession(string appName, DateTime? at = null)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = "UPDATE meeting_sessions SET end_time = $end WHERE app_name = $appName AND end_time IS NULL";
            cmd.Parameters.AddWithValue("$end", ToDb(at ?? DateTime.Now));
            cmd.Parameters.AddWithValue("$appName", appName);
            cmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Log.Error($"EndOpenMeetingSession failed: {ex.Message}");
        }
    }

    public List<MeetingSession> MeetingSessions(DateTime start, DateTime end)
    {
        var result = new List<MeetingSession>();
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                SELECT id, app_name, start_time, end_time FROM meeting_sessions
                WHERE start_time < $end AND (end_time IS NULL OR end_time > $start)
                ORDER BY start_time ASC
                """;
            cmd.Parameters.AddWithValue("$start", ToDb(start));
            cmd.Parameters.AddWithValue("$end", ToDb(end));
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add(new MeetingSession
                {
                    Id = reader.GetInt64(0),
                    AppName = reader.GetString(1),
                    StartTime = FromDb(reader.GetString(2)),
                    EndTime = reader.IsDBNull(3) ? null : FromDb(reader.GetString(3))
                });
            }
        }
        catch (Exception ex)
        {
            Log.Error($"MeetingSessions query failed: {ex.Message}");
        }
        return result;
    }

    public List<MeetingSession> MeetingSessionsOnDay(DateTime day) => MeetingSessions(day.Date, day.Date.AddDays(1));

    public void CloseAllOpenMeetingSessions(DateTime? at = null)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = "UPDATE meeting_sessions SET end_time = $end WHERE end_time IS NULL";
            cmd.Parameters.AddWithValue("$end", ToDb(at ?? DateTime.Now));
            cmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Log.Error($"CloseAllOpenMeetingSessions failed: {ex.Message}");
        }
    }

    // MARK: - Screenshots

    public long? RecordScreenshot(DateTime timestamp, string filePath, int? activityScore, long? appIntervalId)
    {
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                INSERT INTO screenshots (timestamp, file_path, activity_score, app_interval_id)
                VALUES ($timestamp, $filePath, $score, $intervalId);
                SELECT last_insert_rowid();
                """;
            cmd.Parameters.AddWithValue("$timestamp", ToDb(timestamp));
            cmd.Parameters.AddWithValue("$filePath", filePath);
            cmd.Parameters.AddWithValue("$score", (object?)activityScore ?? DBNull.Value);
            cmd.Parameters.AddWithValue("$intervalId", (object?)appIntervalId ?? DBNull.Value);
            return (long)cmd.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            Log.Error($"RecordScreenshot failed: {ex.Message}");
            return null;
        }
    }

    public List<Screenshot> ScreenshotsOnDay(DateTime day)
    {
        var (start, end) = (day.Date, day.Date.AddDays(1));
        var result = new List<Screenshot>();
        try
        {
            using var db = DatabaseManager.Shared.OpenConnection();
            using var cmd = db.CreateCommand();
            cmd.CommandText = """
                SELECT id, timestamp, file_path, activity_score, app_interval_id
                FROM screenshots WHERE timestamp >= $start AND timestamp < $end
                ORDER BY timestamp ASC
                """;
            cmd.Parameters.AddWithValue("$start", ToDb(start));
            cmd.Parameters.AddWithValue("$end", ToDb(end));
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add(new Screenshot
                {
                    Id = reader.GetInt64(0),
                    Timestamp = FromDb(reader.GetString(1)),
                    FilePath = reader.GetString(2),
                    ActivityScoreValue = reader.IsDBNull(3) ? null : reader.GetInt32(3),
                    AppIntervalId = reader.IsDBNull(4) ? null : reader.GetInt64(4)
                });
            }
        }
        catch (Exception ex)
        {
            Log.Error($"ScreenshotsOnDay failed: {ex.Message}");
        }
        return result;
    }
}
