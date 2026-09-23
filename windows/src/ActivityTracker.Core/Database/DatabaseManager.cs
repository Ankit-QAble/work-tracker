using System;
using System.IO;
using Microsoft.Data.Sqlite;

namespace ActivityTracker.Core.Database;

/// <summary>
/// Owns the on-disk SQLite database and schema creation. All data lives under
/// %LOCALAPPDATA%\ActivityTracker\ — nothing leaves this machine. Mirrors the
/// macOS app's schema (see the Swift project's DatabaseManager.swift) for
/// consistency, though the two are entirely separate, never-synced databases.
/// </summary>
public sealed class DatabaseManager
{
    private static readonly Lazy<DatabaseManager> _shared = new(() => new DatabaseManager());
    public static DatabaseManager Shared => _shared.Value;

    public string DatabasePath { get; }
    private readonly string _connectionString;

    /// <summary>
    /// Explicit test-only override for AppDataDirectory. Deliberately a real,
    /// in-code switch rather than relying on an environment variable — an
    /// earlier attempt to isolate a test via the Windows-only LOCALAPPDATA env
    /// var silently no-opped on macOS (SpecialFolder.LocalApplicationData
    /// doesn't consult it there) and wrote test data straight into the real
    /// production database. Must be set before Shared/AppDataDirectory is
    /// first accessed.
    /// </summary>
    public static string? TestOverrideDirectory { get; set; }

    public static string AppDataDirectory
    {
        get
        {
            var dir = TestOverrideDirectory
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ActivityTracker");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string ScreenshotsDirectory
    {
        get
        {
            var dir = Path.Combine(AppDataDirectory, "screenshots");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    private DatabaseManager()
    {
        DatabasePath = Path.Combine(AppDataDirectory, "activity.sqlite");
        _connectionString = new SqliteConnectionStringBuilder { DataSource = DatabasePath }.ToString();
        Migrate();
        Log.Info($"Database ready at {DatabasePath}");
    }

    public SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        return connection;
    }

    private void Migrate()
    {
        using var db = OpenConnection();
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS app_intervals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                window_title TEXT,
                url TEXT,
                domain TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT,
                is_idle INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_app_intervals_start ON app_intervals(start_time);
            CREATE INDEX IF NOT EXISTS idx_app_intervals_domain ON app_intervals(domain);

            CREATE TABLE IF NOT EXISTS activity_scores (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                minute_timestamp TEXT NOT NULL,
                event_count INTEGER NOT NULL,
                score INTEGER NOT NULL,
                app_interval_id INTEGER REFERENCES app_intervals(id) ON DELETE SET NULL
            );
            CREATE INDEX IF NOT EXISTS idx_activity_scores_minute ON activity_scores(minute_timestamp);

            CREATE TABLE IF NOT EXISTS screenshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                file_path TEXT NOT NULL,
                activity_score INTEGER,
                app_interval_id INTEGER REFERENCES app_intervals(id) ON DELETE SET NULL
            );
            CREATE INDEX IF NOT EXISTS idx_screenshots_timestamp ON screenshots(timestamp);

            CREATE TABLE IF NOT EXISTS meeting_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_meeting_sessions_start ON meeting_sessions(start_time);
            """;
        cmd.ExecuteNonQuery();
    }
}

/// <summary>
/// Tiny logging shim — writes to Console (visible via `dotnet run` or a
/// terminal) and to a rolling log file under the app-data directory, since a
/// tray app launched by double-click has no attached console to see Console
/// output in. No key content, no PII beyond what's explicitly tracked.
/// </summary>
public static class Log
{
    private static readonly string LogPath = Path.Combine(DatabaseManager.AppDataDirectory, "app.log");
    private static readonly object Lock = new();

    public static void Info(string message) => Write("INFO", message);
    public static void Error(string message) => Write("ERROR", message);

    private static void Write(string level, string message)
    {
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [{level}] {message}";
        Console.WriteLine(line);
        try
        {
            lock (Lock)
            {
                File.AppendAllText(LogPath, line + Environment.NewLine);
            }
        }
        catch
        {
            // Logging must never crash the app.
        }
    }
}
