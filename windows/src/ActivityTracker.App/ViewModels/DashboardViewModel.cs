using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ActivityTracker.Core.Database;
using ActivityTracker.Core.Models;

namespace ActivityTracker.App.ViewModels;

public partial class AppTimeRow : ObservableObject
{
    public required string AppName { get; init; }
    public required string DurationText { get; init; }
    public required double Fraction { get; init; } // 0-1, for a simple bar
}

public partial class DashboardViewModel : ViewModelBase
{
    [ObservableProperty]
    public partial DateTime SelectedDay { get; set; } = DateTime.Now;

    [ObservableProperty]
    public partial string DateLabel { get; set; } = "";

    [ObservableProperty]
    public partial string TrackedTimeText { get; set; } = "—";

    [ObservableProperty]
    public partial string IdleTimeText { get; set; } = "—";

    [ObservableProperty]
    public partial string MeetingTimeText { get; set; } = "—";

    [ObservableProperty]
    public partial string TopAppText { get; set; } = "—";

    [ObservableProperty]
    public partial string AvgActivityText { get; set; } = "—";

    public ObservableCollection<AppTimeRow> AppRows { get; } = new();

    private bool _isPinnedToToday = true;
    private readonly ActivityStore _store = ActivityStore.Shared;

    public DashboardViewModel()
    {
        Reload();
    }

    /// <summary>Call when the Dashboard is opened from closed — jumps to today.</summary>
    public void ResetToToday()
    {
        SelectedDay = DateTime.Now;
        _isPinnedToToday = true;
        Reload();
    }

    /// <summary>Called on the periodic auto-refresh tick while the window is visible.</summary>
    public void AutoRefresh()
    {
        if (_isPinnedToToday) SelectedDay = DateTime.Now;
        Reload();
    }

    [RelayCommand]
    private void PreviousDay()
    {
        SelectedDay = SelectedDay.AddDays(-1);
        _isPinnedToToday = false;
        Reload();
    }

    [RelayCommand(CanExecute = nameof(CanGoNext))]
    private void NextDay()
    {
        var next = SelectedDay.AddDays(1);
        SelectedDay = next > DateTime.Now ? DateTime.Now : next;
        _isPinnedToToday = SelectedDay.Date == DateTime.Now.Date;
        Reload();
    }

    private bool CanGoNext() => SelectedDay.Date < DateTime.Now.Date;

    [RelayCommand]
    private void Today()
    {
        SelectedDay = DateTime.Now;
        _isPinnedToToday = true;
        Reload();
    }

    [RelayCommand]
    private void Refresh() => Reload();

    [RelayCommand]
    private void ExportDay() => Export(ExportRange.Day);

    [RelayCommand]
    private void ExportWeek() => Export(ExportRange.Week);

    [RelayCommand]
    private void ExportMonth() => Export(ExportRange.Month);

    private void Export(ExportRange range)
    {
        try
        {
            var csv = CSVExporter.Generate(range, SelectedDay);
            var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            Directory.CreateDirectory(downloads);
            var path = Path.Combine(downloads, CSVExporter.SuggestedFilename(range, SelectedDay));
            File.WriteAllText(path, csv);
            Log.Info($"Exported CSV to {path}");
        }
        catch (Exception ex)
        {
            Log.Error($"CSV export failed: {ex.Message}");
        }
    }

    public void Reload()
    {
        DateLabel = SelectedDay.ToString("dddd, d MMMM yyyy");
        NextDayCommand.NotifyCanExecuteChanged();

        var appSummary = _store.AppTimeSummary(SelectedDay);
        var intervals = _store.IntervalsOnDay(SelectedDay);
        var meetings = _store.MeetingSessionsOnDay(SelectedDay);
        var scores = _store.ActivityScoresOnDay(SelectedDay);

        var trackedSeconds = appSummary.Sum(a => a.TotalTime.TotalSeconds);
        TrackedTimeText = FormatDuration(trackedSeconds);

        var (dayStart, dayEnd) = (SelectedDay.Date, SelectedDay.Date.AddDays(1));
        var idleSeconds = intervals.Where(i => i.IsIdle).Sum(i =>
        {
            var s = i.StartTime < dayStart ? dayStart : i.StartTime;
            var e = (i.EndTime ?? DateTime.Now) > dayEnd ? dayEnd : (i.EndTime ?? DateTime.Now);
            return Math.Max(0, (e - s).TotalSeconds);
        });
        IdleTimeText = FormatDuration(idleSeconds);

        var meetingSeconds = meetings.Sum(m =>
        {
            var s = m.StartTime < dayStart ? dayStart : m.StartTime;
            var e = (m.EndTime ?? DateTime.Now) > dayEnd ? dayEnd : (m.EndTime ?? DateTime.Now);
            return Math.Max(0, (e - s).TotalSeconds);
        });
        MeetingTimeText = meetings.Count > 0 ? FormatDuration(meetingSeconds) : "—";

        TopAppText = appSummary.Count > 0 ? appSummary[0].AppName : "—";

        // Only average minutes tied to a non-idle interval — see the macOS
        // port's fix for why (idle minutes always score 0 and would otherwise
        // just measure how much of the day you were away).
        var idleIntervalIds = intervals.Where(i => i.IsIdle).Select(i => i.Id).ToHashSet();
        var activeScores = scores.Where(s => s.AppIntervalId == null || !idleIntervalIds.Contains(s.AppIntervalId)).ToList();
        AvgActivityText = activeScores.Count > 0 ? Math.Round(activeScores.Average(s => s.Score)).ToString() : "—";

        AppRows.Clear();
        var maxSeconds = appSummary.Count > 0 ? appSummary[0].TotalTime.TotalSeconds : 1;
        foreach (var row in appSummary.Take(10))
        {
            AppRows.Add(new AppTimeRow
            {
                AppName = row.AppName,
                DurationText = FormatDuration(row.TotalTime.TotalSeconds),
                Fraction = maxSeconds > 0 ? row.TotalTime.TotalSeconds / maxSeconds : 0
            });
        }
    }

    private static string FormatDuration(double seconds)
    {
        var totalMinutes = (int)(seconds / 60);
        var hours = totalMinutes / 60;
        var minutes = totalMinutes % 60;
        return hours > 0 ? $"{hours}h {minutes}m" : $"{minutes}m";
    }
}
