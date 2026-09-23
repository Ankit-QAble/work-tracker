using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using ActivityTracker.Core.Database;

namespace ActivityTracker.Core.Models;

/// <summary>
/// User-configurable settings, persisted as a JSON file under the app-data
/// directory (the Windows equivalent of the macOS app's UserDefaults-backed
/// AppSettings — Windows doesn't have as convenient a per-app plist store in
/// raw .NET, and a JSON file keeps everything consistent with "all data lives
/// under this one directory").
/// </summary>
public sealed class AppSettings
{
    private static readonly Lazy<AppSettings> _shared = new(Load);
    public static AppSettings Shared => _shared.Value;

    public double IdleThresholdSeconds { get; set; } = 180;
    public bool ScreenshotsEnabled { get; set; } = false;
    public double ScreenshotIntervalMinutes { get; set; } = 10;
    public List<string> ExcludedApps { get; set; } = new();
    public bool IdlePromptEnabled { get; set; } = true;
    public double IdlePromptThresholdSeconds { get; set; } = 300;
    public double TimelineStartHour { get; set; } = 9;
    public double TimelineEndHour { get; set; } = 23;

    private static string SettingsPath => Path.Combine(DatabaseManager.AppDataDirectory, "settings.json");

    private static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                var loaded = JsonSerializer.Deserialize<AppSettings>(json);
                if (loaded != null) return loaded;
            }
        }
        catch (Exception ex)
        {
            Log.Error($"AppSettings load failed, using defaults: {ex.Message}");
        }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsPath, json);
        }
        catch (Exception ex)
        {
            Log.Error($"AppSettings save failed: {ex.Message}");
        }
    }

    public bool IsExcluded(string appName) => ExcludedApps.Contains(appName);
}
