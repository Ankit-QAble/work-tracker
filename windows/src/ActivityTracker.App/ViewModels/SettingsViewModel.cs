using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ActivityTracker.Core.Models;

namespace ActivityTracker.App.ViewModels;

public partial class SettingsViewModel : ViewModelBase
{
    private readonly AppSettings _settings = AppSettings.Shared;

    [ObservableProperty]
    public partial double IdleThresholdSeconds { get; set; }

    [ObservableProperty]
    public partial bool IdlePromptEnabled { get; set; }

    [ObservableProperty]
    public partial double IdlePromptThresholdSeconds { get; set; }

    [ObservableProperty]
    public partial string NewExcludedApp { get; set; } = "";

    public ObservableCollection<string> ExcludedApps { get; } = new();

    public SettingsViewModel()
    {
        IdleThresholdSeconds = _settings.IdleThresholdSeconds;
        IdlePromptEnabled = _settings.IdlePromptEnabled;
        IdlePromptThresholdSeconds = _settings.IdlePromptThresholdSeconds;
        foreach (var app in _settings.ExcludedApps) ExcludedApps.Add(app);
    }

    partial void OnIdleThresholdSecondsChanged(double value) { _settings.IdleThresholdSeconds = value; _settings.Save(); }
    partial void OnIdlePromptEnabledChanged(bool value) { _settings.IdlePromptEnabled = value; _settings.Save(); }
    partial void OnIdlePromptThresholdSecondsChanged(double value) { _settings.IdlePromptThresholdSeconds = value; _settings.Save(); }

    [RelayCommand]
    private void AddExcludedApp()
    {
        var trimmed = NewExcludedApp.Trim();
        if (string.IsNullOrEmpty(trimmed) || ExcludedApps.Contains(trimmed)) return;
        ExcludedApps.Add(trimmed);
        _settings.ExcludedApps.Add(trimmed);
        _settings.Save();
        NewExcludedApp = "";
    }

    [RelayCommand]
    private void RemoveExcludedApp(string app)
    {
        ExcludedApps.Remove(app);
        _settings.ExcludedApps.Remove(app);
        _settings.Save();
    }
}
