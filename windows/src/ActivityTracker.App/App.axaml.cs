using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Platform;
using Avalonia.Threading;
using ActivityTracker.App.ViewModels;
using ActivityTracker.App.Views;
using ActivityTracker.Core.Database;
using ActivityTracker.Core.Tracking;

namespace ActivityTracker.App;

public partial class App : Application
{
    private DashboardWindow? _dashboardWindow;
    private SettingsWindow? _settingsWindow;
    private NativeMenuItem? _statusItem;
    private NativeMenuItem? _pauseResumeItem;
    private DispatcherTimer? _dashboardRefreshTimer;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Menu-bar/tray-only — no main window, and don't quit just because
            // the Dashboard/Settings windows get hidden (they're Hide(), not
            // Close()'d — see each window's OnClosing override).
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;

            SetupTrayIcon(desktop);

            TrackingCoordinator.Shared.StatusChanged += OnStatusChanged;
            TrackingCoordinator.Shared.IdleResumePromptRequested += OnIdleResumePromptRequested;
            TrackingCoordinator.Shared.Start();
            OnStatusChanged(TrackingCoordinator.Shared.Status);

            _dashboardRefreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
            _dashboardRefreshTimer.Tick += (_, _) =>
            {
                if (_dashboardWindow?.IsVisible == true) _dashboardWindow.ViewModel.AutoRefresh();
            };
            _dashboardRefreshTimer.Start();

            Log.Info($"ActivityTracker launched. Data directory: {DatabaseManager.AppDataDirectory}");
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void SetupTrayIcon(IClassicDesktopStyleApplicationLifetime desktop)
    {
        _statusItem = new NativeMenuItem("Status: Tracking") { IsEnabled = false };
        _pauseResumeItem = new NativeMenuItem("Pause Tracking");
        _pauseResumeItem.Click += (_, _) => TrackingCoordinator.Shared.TogglePause();

        var openDashboardItem = new NativeMenuItem("Open Dashboard…");
        openDashboardItem.Click += (_, _) => ShowDashboard();

        var settingsItem = new NativeMenuItem("Settings…");
        settingsItem.Click += (_, _) => ShowSettings();

        var quitItem = new NativeMenuItem("Quit ActivityTracker");
        quitItem.Click += (_, _) =>
        {
            TrackingCoordinator.Shared.Shutdown();
            desktop.Shutdown();
        };

        var menu = new NativeMenu
        {
            Items =
            {
                _statusItem,
                new NativeMenuItemSeparator(),
                _pauseResumeItem,
                openDashboardItem,
                settingsItem,
                new NativeMenuItemSeparator(),
                quitItem,
                new NativeMenuItemSeparator(),
                new NativeMenuItem("Developed by QAble") { IsEnabled = false },
            },
        };

        var trayIcon = new TrayIcon
        {
            Icon = new WindowIcon(AssetLoader.Open(new Uri("avares://ActivityTracker.App/Assets/avalonia-logo.ico"))),
            ToolTipText = "ActivityTracker — Tracking",
            Menu = menu,
        };
        trayIcon.Clicked += (_, _) => ShowDashboard();

        TrayIcon.SetIcons(this, new TrayIcons { trayIcon });
    }

    private void ShowDashboard()
    {
        var wasVisible = _dashboardWindow?.IsVisible == true;
        if (_dashboardWindow == null)
        {
            _dashboardWindow = new DashboardWindow { DataContext = new DashboardViewModel() };
        }
        if (!wasVisible)
        {
            // Reset to today whenever opened from closed/hidden — mirrors the
            // macOS app's fix for the same "reopened dashboard shows stale day" issue.
            _dashboardWindow.ViewModel.ResetToToday();
        }
        _dashboardWindow.Show();
        _dashboardWindow.Activate();
    }

    private void ShowSettings()
    {
        _settingsWindow ??= new SettingsWindow { DataContext = new SettingsViewModel() };
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void OnStatusChanged(TrackingStatus status)
    {
        Dispatcher.UIThread.Post(() =>
        {
            if (_statusItem != null) _statusItem.Header = $"Status: {status}";
            if (_pauseResumeItem != null) _pauseResumeItem.Header = status == TrackingStatus.Paused ? "Resume Tracking" : "Pause Tracking";

            var icons = TrayIcon.GetIcons(this);
            if (icons?.Count > 0) icons[0].ToolTipText = $"ActivityTracker — {status}";
        });
    }

    private void OnIdleResumePromptRequested(TimeSpan idleDuration, string previousApp, Action onKeepAsWork)
    {
        Dispatcher.UIThread.Post(() =>
        {
            var window = new IdleResumePromptWindow(idleDuration, previousApp, onKeepAsWork);
            window.Show();
        });
    }
}
