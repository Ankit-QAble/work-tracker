using Avalonia;
using System;
using ActivityTracker.Core.Database;

namespace ActivityTracker.App;

sealed class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    [STAThread]
    public static void Main(string[] args)
    {
        // Explicit, in-code test override — checked and verified here rather
        // than relying on an OS-specific env var name assumed to control
        // Environment.SpecialFolder resolution (that assumption is exactly
        // what caused an earlier mistake during this port: LOCALAPPDATA has
        // no effect on macOS, and the real resolved path collided with the
        // production database).
        var testDataDir = Environment.GetEnvironmentVariable("ACTIVITYTRACKER_DATA_DIR");
        if (!string.IsNullOrEmpty(testDataDir))
        {
            DatabaseManager.TestOverrideDirectory = testDataDir;
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .WithInterFont()
            .LogToTrace();
}
