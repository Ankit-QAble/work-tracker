using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace ActivityTracker.Core.Database;

public enum ExportRange { Day, Week, Month }

/// <summary>
/// Renders tracked activity to CSV — opens directly in Excel/Numbers/Sheets.
/// Rows are grouped by (day, app, domain, type) with a summed duration and
/// visit count, not one row per raw app-switch (a day of normal use can
/// otherwise produce hundreds of rows for the same handful of apps). Mirrors
/// the macOS app's CSVExporter.
/// </summary>
public static class CSVExporter
{
    private readonly record struct GroupKey(string Date, string AppName, string Domain, string Type);
    private sealed class Accumulator
    {
        public double TotalSeconds;
        public int Visits;
    }

    public static (DateTime Start, DateTime End) Bounds(ExportRange range, DateTime day)
    {
        switch (range)
        {
            case ExportRange.Day:
                var dayStart = day.Date;
                return (dayStart, dayStart.AddDays(1));
            case ExportRange.Week:
                var diff = (7 + (day.DayOfWeek - DayOfWeek.Monday)) % 7;
                var weekStart = day.Date.AddDays(-diff);
                return (weekStart, weekStart.AddDays(7));
            case ExportRange.Month:
                var monthStart = new DateTime(day.Year, day.Month, 1);
                return (monthStart, monthStart.AddMonths(1));
            default:
                throw new ArgumentOutOfRangeException(nameof(range));
        }
    }

    public static string Generate(ExportRange range, DateTime anchoredOn)
    {
        var (start, end) = Bounds(range, anchoredOn);
        var groups = new Dictionary<GroupKey, Accumulator>();

        foreach (var interval in ActivityStore.Shared.Intervals(start, end))
        {
            var clampedStart = interval.StartTime < start ? start : interval.StartTime;
            var clampedEnd = (interval.EndTime ?? DateTime.Now) > end ? end : (interval.EndTime ?? DateTime.Now);
            if (clampedEnd <= clampedStart) continue;

            var type = interval.IsIdle ? "Idle" : "Active";
            var domain = interval.IsIdle ? "" : (interval.Domain ?? "");

            foreach (var (segStart, segEnd) in SplitByDay(clampedStart, clampedEnd))
            {
                var seconds = (segEnd - segStart).TotalSeconds;
                if (seconds <= 0) continue;
                var key = new GroupKey(segStart.ToString("yyyy-MM-dd"), interval.AppName, domain, type);
                var acc = groups.TryGetValue(key, out var existing) ? existing : new Accumulator();
                acc.TotalSeconds += seconds;
                acc.Visits += 1;
                groups[key] = acc;
            }
        }

        foreach (var meeting in ActivityStore.Shared.MeetingSessions(start, end))
        {
            var clampedStart = meeting.StartTime < start ? start : meeting.StartTime;
            var clampedEnd = (meeting.EndTime ?? DateTime.Now) > end ? end : (meeting.EndTime ?? DateTime.Now);
            if (clampedEnd <= clampedStart) continue;

            foreach (var (segStart, segEnd) in SplitByDay(clampedStart, clampedEnd))
            {
                var seconds = (segEnd - segStart).TotalSeconds;
                if (seconds <= 0) continue;
                var key = new GroupKey(segStart.ToString("yyyy-MM-dd"), meeting.AppName, "", "Meeting");
                var acc = groups.TryGetValue(key, out var existing) ? existing : new Accumulator();
                acc.TotalSeconds += seconds;
                acc.Visits += 1;
                groups[key] = acc;
            }
        }

        var typeOrder = new Dictionary<string, int> { ["Active"] = 0, ["Meeting"] = 1, ["Idle"] = 2 };
        var rows = groups
            .Select(kv => (kv.Key, kv.Value, Minutes: (int)Math.Round(kv.Value.TotalSeconds / 60)))
            .Where(r => r.Minutes >= 1)
            .OrderBy(r => r.Key.Date)
            .ThenBy(r => typeOrder.GetValueOrDefault(r.Key.Type, 99))
            .ThenByDescending(r => r.Value.TotalSeconds);

        var sb = new StringBuilder();
        sb.AppendLine("Date,App,Domain,Type,Total Duration (min),Visits");
        foreach (var (key, acc, minutes) in rows)
        {
            sb.AppendLine(string.Join(",",
                Escape(key.Date), Escape(key.AppName), Escape(key.Domain), Escape(key.Type),
                minutes.ToString(), acc.Visits.ToString()));
        }
        return sb.ToString();
    }

    public static string SuggestedFilename(ExportRange range, DateTime anchoredOn) =>
        $"ActivityTracker_{range.ToString().ToLowerInvariant()}_{anchoredOn:yyyy-MM-dd}.csv";

    private static IEnumerable<(DateTime, DateTime)> SplitByDay(DateTime start, DateTime end)
    {
        var cursor = start;
        while (cursor < end)
        {
            var dayStart = cursor.Date;
            var nextDayStart = dayStart.AddDays(1);
            var segmentEnd = end < nextDayStart ? end : nextDayStart;
            yield return (cursor, segmentEnd);
            cursor = segmentEnd;
        }
    }

    private static string Escape(string field)
    {
        if (field.Contains(',') || field.Contains('"') || field.Contains('\n'))
            return $"\"{field.Replace("\"", "\"\"")}\"";
        return field;
    }
}
