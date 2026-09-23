using Avalonia.Controls;
using ActivityTracker.App.ViewModels;

namespace ActivityTracker.App.Views;

public partial class DashboardWindow : Window
{
    public DashboardWindow()
    {
        InitializeComponent();
    }

    public DashboardViewModel ViewModel => (DashboardViewModel)DataContext!;

    /// <summary>
    /// Hide rather than close, so the window (and its ViewModel state, like
    /// which day is selected) is reused rather than recreated — mirroring the
    /// macOS app's window-reuse pattern, which is what makes ResetToToday()
    /// meaningful (there'd be nothing to reset if a fresh one were created
    /// every time).
    /// </summary>
    protected override void OnClosing(WindowClosingEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }
}
