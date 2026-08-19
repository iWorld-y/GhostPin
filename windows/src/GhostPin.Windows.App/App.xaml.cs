using System.Windows;

namespace GhostPin.Windows.App;

public partial class App : System.Windows.Application
{
    private HudController? _controller;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var window = new HudWindow();
        _controller = new HudController(window, Dispatcher);
        try
        {
            await _controller.StartAsync();
        }
        catch (Exception error)
        {
            _controller.ViewModel.SetDiagnostic(error);
            _controller.ShowHud();
        }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_controller is not null)
        {
            await _controller.StopAsync();
        }
        base.OnExit(e);
    }
}
