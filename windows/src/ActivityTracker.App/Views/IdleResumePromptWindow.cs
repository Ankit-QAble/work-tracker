using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace ActivityTracker.App.Views;

/// <summary>
/// A small floating, always-on-top window shown when returning from an idle
/// stretch longer than the configured threshold — the Windows port of the
/// macOS app's IdleResumePromptController. Auto-dismisses (defaulting to
/// "stay idle", i.e. no data change) if ignored, so it can never block
/// tracking or pile up waiting for a response.
/// </summary>
public sealed class IdleResumePromptWindow : Window
{
    private readonly DispatcherTimer _autoDismissTimer;

    public IdleResumePromptWindow(TimeSpan idleDuration, string previousApp, Action onKeepAsWork)
    {
        Width = 300;
        Height = 140;
        CanResize = false;
        Topmost = true;
        ShowInTaskbar = false;
        Title = "ActivityTracker";

        var minutes = Math.Max(1, (int)idleDuration.TotalMinutes);
        var message = new TextBlock
        {
            Text = $"You were idle for {minutes}m. Count it as {previousApp}, or leave it as idle?",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Margin = new Thickness(0, 0, 0, 12),
        };

        var keepButton = new Button { Content = $"Keep as {previousApp}" };
        keepButton.Click += (_, _) => { onKeepAsWork(); Close(); };

        var discardButton = new Button { Content = "Discard" };
        discardButton.Click += (_, _) => Close();

        Content = new StackPanel
        {
            Margin = new Thickness(16),
            Children =
            {
                new TextBlock { Text = "Welcome back", FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 0, 0, 8) },
                message,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 8,
                    Children = { keepButton, discardButton },
                },
            },
        };

        Opened += (_, _) =>
        {
            var screen = Screens.Primary;
            if (screen != null)
            {
                var wa = screen.WorkingArea;
                Position = new PixelPoint(wa.X + wa.Width - (int)Width - 16, wa.Y + 16);
            }
        };

        _autoDismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
        _autoDismissTimer.Tick += (_, _) => { _autoDismissTimer.Stop(); Close(); };
        _autoDismissTimer.Start();

        Closed += (_, _) => _autoDismissTimer.Stop();
    }
}
