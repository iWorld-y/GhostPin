using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using GhostPin.Windows.App.ViewModels;

namespace GhostPin.Windows.App;

public partial class HudWindow : Window
{
    public HudWindow()
    {
        InitializeComponent();
        DataContext = new HudViewModel();
    }

    public event Action<Guid>? AdvanceRequested;
    public event Action? HideRequested;

    public HudViewModel ViewModel => (HudViewModel)DataContext;

    private void OnAdvanceClick(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: TaskCardViewModel card })
        {
            AdvanceRequested?.Invoke(card.Id);
        }
        e.Handled = true;
    }

    private void OnCloseClick(object sender, RoutedEventArgs e)
    {
        HideRequested?.Invoke();
        e.Handled = true;
    }

    private void OnRootMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left || !ViewModel.IsInteractive || IsWithinInteractiveControl(e.OriginalSource as DependencyObject))
        {
            return;
        }

        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            // 窗口正在关闭时忽略尾随鼠标消息。
        }
        e.Handled = true;
    }

    private static bool IsWithinInteractiveControl(DependencyObject? source)
    {
        for (var current = source; current is not null;)
        {
            if (current is System.Windows.Controls.Button or
                System.Windows.Controls.ScrollViewer or
                System.Windows.Controls.Primitives.ScrollBar)
            {
                return true;
            }

            current = current is System.Windows.Media.Visual or System.Windows.Media.Media3D.Visual3D
                ? VisualTreeHelper.GetParent(current)
                : current is ContentElement contentElement
                    ? ContentOperations.GetParent(contentElement)
                    : LogicalTreeHelper.GetParent(current);
        }

        return false;
    }
}
