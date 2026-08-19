using System.Windows;
using System.Windows.Threading;
using System.IO;
using GhostPin.Windows.App.Platform;
using GhostPin.Windows.App.ViewModels;
using GhostPin.Windows.Core.Models;
using GhostPin.Windows.Core.Projection;
using GhostPin.Windows.Core.Settings;
using GhostPin.Windows.Core.Storage;

namespace GhostPin.Windows.App;

/// <summary>只编排 Core、文件监听、窗口宿主和通知区域，不承载任务排序或 JSON 细节。</summary>
public sealed class HudController
{
    private readonly HudWindow _window;
    private readonly Dispatcher _dispatcher;
    private readonly WindowsStoragePaths _paths;
    private readonly SettingsRepository _settingsRepository;
    private readonly TodoRepository _todoRepository;
    private readonly TodoFileWatcher _watcher;
    private readonly HudWindowHost _windowHost;
    private readonly WindowPlacementService _placementService = new();
    private HudSettings _settings = HudSettings.Default;
    private System.Windows.Forms.NotifyIcon? _notifyIcon;
    private System.Windows.Forms.ToolStripMenuItem? _visibilityMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _modeMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _topmostMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _scopeAllMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _scopeTodayMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _opacity70MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _opacity85MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _opacity92MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _opacity100MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _maxItems5MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _maxItems8MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _maxItems12MenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _maxItems20MenuItem;
    private bool _isStopping;
    private bool _allowWindowClose;
    private bool _isStarted;

    public HudController(HudWindow window, Dispatcher dispatcher, WindowsStoragePaths? paths = null)
    {
        _window = window ?? throw new ArgumentNullException(nameof(window));
        _dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        _paths = paths ?? WindowsStoragePaths.Resolve();
        _paths.EnsureDirectory();
        _settingsRepository = new SettingsRepository(_paths.SettingsFile);
        _todoRepository = new TodoRepository(_paths.TodosFile);
        _watcher = new TodoFileWatcher(_paths.RootDirectory, token => _todoRepository.LoadAsync(token), "todos.json");
        _windowHost = new HudWindowHost(_window);

        _window.AdvanceRequested += OnAdvanceRequested;
        _window.HideRequested += HideHud;
        _window.Closing += OnWindowClosing;
        _window.LocationChanged += OnWindowGeometryChanged;
        _window.SizeChanged += OnWindowGeometryChanged;
        _todoRepository.SnapshotChanged += OnSnapshotChanged;
        _todoRepository.DiagnosticError += OnRepositoryDiagnosticError;
        _watcher.DiagnosticError += OnDiagnosticError;
        _windowHost.DiagnosticError += OnDiagnosticError;
    }

    public HudViewModel ViewModel => _window.ViewModel;
    public HudSettings Settings => _settings;
    public TodoRepository TodoRepository => _todoRepository;
    public HudWindowHost WindowHost => _windowHost;

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        _settings = await _settingsRepository.LoadAsync(cancellationToken);
        var settingsError = _settingsRepository.LastError;
        if (settingsError is not null)
        {
            SetDiagnostic(settingsError);
        }

        PrepareWindowHandle();
        ApplySettingsToWindow();
        await _todoRepository.LoadAsync(cancellationToken);
        try
        {
            _watcher.Start();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
        try
        {
            CreateNotifyIcon();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
        RefreshView();

        try
        {
            if (_settings.IsVisible)
            {
                _windowHost.ShowWithoutActivation();
            }
            else
            {
                _windowHost.Hide();
            }
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
        }
        _isStarted = true;
        UpdateMenuState();
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (_isStopping)
        {
            return;
        }

        _isStopping = true;
        await _watcher.StopAsync();
        try
        {
            CaptureWindowPlacement();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
        }
        await SaveSettingsSafeAsync(cancellationToken);
        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }

        _allowWindowClose = true;
        _windowHost.Dispose();
        if (_window.IsVisible)
        {
            _window.Close();
        }
        await _todoRepository.DisposeAsync();
    }

    public void ShowHud()
    {
        if (_isStopping) return;
        try
        {
            _windowHost.ShowWithoutActivation();
            _settings.IsVisible = true;
            UpdateMenuState();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
    }

    public void HideHud()
    {
        if (_isStopping) return;
        try
        {
            _windowHost.Hide();
            _settings.IsVisible = false;
            UpdateMenuState();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
    }

    public void SetInteractionMode(HudMode mode)
    {
        if (_isStopping) return;
        try
        {
            _windowHost.SetInteractionMode(mode);
            _settings.Mode = mode;
            ViewModel.SetMode(mode);
            UpdateMenuState();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
    }

    public void SetTopmost(bool isTopmost)
    {
        if (_isStopping) return;
        try
        {
            _windowHost.SetTopmost(isTopmost);
            _settings.IsTopmost = isTopmost;
            UpdateMenuState();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
    }

    public void SetScope(HudScope scope)
    {
        if (_isStopping) return;
        _settings.Scope = scope;
        RefreshView();
        UpdateMenuState();
        _ = SaveSettingsSafeAsync();
    }

    public void SetHudOpacity(double opacity)
    {
        if (_isStopping) return;
        try
        {
            var normalized = Math.Clamp(opacity, 0.5, 1.0);
            _windowHost.SetOpacity(normalized);
            _settings.Opacity = normalized;
            UpdateMenuState();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            UpdateMenuState();
        }
    }

    public void SetMaxItems(int maxItems)
    {
        if (_isStopping) return;
        _settings.MaxItems = Math.Clamp(maxItems, 1, 100);
        RefreshView();
        UpdateMenuState();
        _ = SaveSettingsSafeAsync();
    }

    public async Task ExitAsync()
    {
        if (_isStopping)
        {
            return;
        }

        await StopAsync();
        Shutdown();
    }

    private void PrepareWindowHandle()
    {
        if (_windowHost.IsInitialized)
        {
            return;
        }

        _window.ShowActivated = false;
        _window.Show();
        _window.Hide();
    }

    private void ApplySettingsToWindow()
    {
        try
        {
            var monitors = _placementService.GetMonitors(_windowHost.Hwnd);
            var rect = _placementService.Restore(_settings.Placement, monitors);
            _windowHost.ApplyPhysicalBounds(rect);
            _windowHost.SetOpacity(_settings.Opacity);
            _windowHost.SetInteractionMode(_settings.Mode);
            _windowHost.SetTopmost(_settings.IsTopmost);
            ViewModel.SetMode(_settings.Mode);
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
            try
            {
                _windowHost.ApplyPhysicalBounds(new System.Windows.Rect(0, 0, 380, 520));
                _windowHost.SetOpacity(_settings.Opacity);
                _windowHost.SetInteractionMode(_settings.Mode);
                ViewModel.SetMode(_settings.Mode);
            }
            catch (Exception fallbackError)
            {
                SetDiagnostic(fallbackError);
            }
        }
    }

    private void CaptureWindowPlacement()
    {
        if (!_windowHost.IsInitialized)
        {
            return;
        }

        _settings.Placement = _placementService.Capture(_windowHost.Hwnd);
    }

    private void RefreshView()
    {
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.BeginInvoke(RefreshView);
            return;
        }

        var now = DateTimeOffset.Now;
        var projection = HudProjection.Project(
            _todoRepository.Snapshot,
            _settings.Scope,
            _settings.MaxItems,
            now);
        ViewModel.Apply(projection, now);
        ViewModel.SetRepositoryDiagnostic(_todoRepository.LastError);
    }

    private void OnSnapshotChanged(object? sender, TodoSnapshotChangedEventArgs args)
    {
        _dispatcher.BeginInvoke(RefreshView, DispatcherPriority.DataBind);
    }

    private void OnDiagnosticError(Exception error)
    {
        SetDiagnostic(error);
    }

    private void OnRepositoryDiagnosticError(Exception error)
    {
        if (_dispatcher.CheckAccess())
        {
            ViewModel.SetRepositoryDiagnostic(error);
        }
        else
        {
            _dispatcher.BeginInvoke(() => ViewModel.SetRepositoryDiagnostic(error));
        }
    }

    private void SetDiagnostic(Exception error)
    {
        if (_dispatcher.CheckAccess())
        {
            ViewModel.SetDiagnostic(error);
        }
        else
        {
            _dispatcher.BeginInvoke(() => ViewModel.SetDiagnostic(error));
        }
    }

    private async void OnAdvanceRequested(Guid id)
    {
        if (_settings.Mode != HudMode.Interactive || _isStopping)
        {
            return;
        }

        try
        {
            if (_todoRepository.IsCoolingDown(id))
            {
                ViewModel.SetAdvanceMessage("请稍候");
                return;
            }

            var updated = await _todoRepository.AdvanceStatusAsync(id);
            if (updated is null)
            {
                ViewModel.SetAdvanceMessage("任务已变化，请稍后刷新");
                return;
            }

            ViewModel.SetAdvanceMessage(updated.Status == TodoStatus.Done ? "已完成" : "已开始");
            RefreshView();
            await Task.Delay(500);
            ViewModel.SetAdvanceMessage(null);
        }
        catch (Exception error)
        {
            ViewModel.SetRepositoryDiagnostic(error);
        }
    }

    private void OnWindowClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (_allowWindowClose || _isStopping)
        {
            return;
        }

        e.Cancel = true;
        HideHud();
    }

    private void OnWindowGeometryChanged(object? sender, EventArgs args)
    {
        if (!_isStarted || _isStopping || !_windowHost.IsInitialized)
        {
            return;
        }

        try
        {
            CaptureWindowPlacement();
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
        }
    }

    private async Task SaveSettingsSafeAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await _settingsRepository.SaveAsync(_settings, cancellationToken);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            SetDiagnostic(error);
        }
    }

    private void CreateNotifyIcon()
    {
        var menu = new System.Windows.Forms.ContextMenuStrip();
        _visibilityMenuItem = new System.Windows.Forms.ToolStripMenuItem();
        _visibilityMenuItem.Click += (_, _) =>
        {
            if (_settings.IsVisible) HideHud(); else ShowHud();
        };
        _modeMenuItem = new System.Windows.Forms.ToolStripMenuItem("交互模式") { CheckOnClick = true };
        _modeMenuItem.Click += (_, _) => SetInteractionMode(_modeMenuItem.Checked ? HudMode.Interactive : HudMode.Passthrough);
        _topmostMenuItem = new System.Windows.Forms.ToolStripMenuItem("始终置顶") { CheckOnClick = true };
        _topmostMenuItem.Click += (_, _) => SetTopmost(_topmostMenuItem.Checked);

        var scopeMenu = new System.Windows.Forms.ToolStripMenuItem("任务范围");
        _scopeAllMenuItem = new System.Windows.Forms.ToolStripMenuItem("全部") { CheckOnClick = true };
        _scopeAllMenuItem.Click += (_, _) => SetScope(HudScope.All);
        _scopeTodayMenuItem = new System.Windows.Forms.ToolStripMenuItem("今天") { CheckOnClick = true };
        _scopeTodayMenuItem.Click += (_, _) => SetScope(HudScope.Today);
        scopeMenu.DropDownItems.Add(_scopeAllMenuItem);
        scopeMenu.DropDownItems.Add(_scopeTodayMenuItem);

        var opacityMenu = new System.Windows.Forms.ToolStripMenuItem("透明度");
        _opacity70MenuItem = new System.Windows.Forms.ToolStripMenuItem("70%") { CheckOnClick = true };
        _opacity70MenuItem.Click += (_, _) => SetHudOpacity(0.70);
        _opacity85MenuItem = new System.Windows.Forms.ToolStripMenuItem("85%") { CheckOnClick = true };
        _opacity85MenuItem.Click += (_, _) => SetHudOpacity(0.85);
        _opacity92MenuItem = new System.Windows.Forms.ToolStripMenuItem("92%") { CheckOnClick = true };
        _opacity92MenuItem.Click += (_, _) => SetHudOpacity(0.92);
        _opacity100MenuItem = new System.Windows.Forms.ToolStripMenuItem("100%") { CheckOnClick = true };
        _opacity100MenuItem.Click += (_, _) => SetHudOpacity(1.0);
        opacityMenu.DropDownItems.Add(_opacity70MenuItem);
        opacityMenu.DropDownItems.Add(_opacity85MenuItem);
        opacityMenu.DropDownItems.Add(_opacity92MenuItem);
        opacityMenu.DropDownItems.Add(_opacity100MenuItem);

        var maxItemsMenu = new System.Windows.Forms.ToolStripMenuItem("最多任务数");
        _maxItems5MenuItem = new System.Windows.Forms.ToolStripMenuItem("5") { CheckOnClick = true };
        _maxItems5MenuItem.Click += (_, _) => SetMaxItems(5);
        _maxItems8MenuItem = new System.Windows.Forms.ToolStripMenuItem("8") { CheckOnClick = true };
        _maxItems8MenuItem.Click += (_, _) => SetMaxItems(8);
        _maxItems12MenuItem = new System.Windows.Forms.ToolStripMenuItem("12") { CheckOnClick = true };
        _maxItems12MenuItem.Click += (_, _) => SetMaxItems(12);
        _maxItems20MenuItem = new System.Windows.Forms.ToolStripMenuItem("20") { CheckOnClick = true };
        _maxItems20MenuItem.Click += (_, _) => SetMaxItems(20);
        maxItemsMenu.DropDownItems.Add(_maxItems5MenuItem);
        maxItemsMenu.DropDownItems.Add(_maxItems8MenuItem);
        maxItemsMenu.DropDownItems.Add(_maxItems12MenuItem);
        maxItemsMenu.DropDownItems.Add(_maxItems20MenuItem);

        var exitItem = new System.Windows.Forms.ToolStripMenuItem("退出 GhostPin");
        exitItem.Click += async (_, _) => await ExitAsync();
        menu.Items.Add(_visibilityMenuItem);
        menu.Items.Add(_modeMenuItem);
        menu.Items.Add(_topmostMenuItem);
        menu.Items.Add(scopeMenu);
        menu.Items.Add(opacityMenu);
        menu.Items.Add(maxItemsMenu);
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(exitItem);

        _notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "GhostPin",
            ContextMenuStrip = menu,
            Visible = true
        };
    }

    private void UpdateMenuState()
    {
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.BeginInvoke(UpdateMenuState);
            return;
        }

        if (_visibilityMenuItem is not null) _visibilityMenuItem.Text = _settings.IsVisible ? "隐藏 HUD" : "显示 HUD";
        if (_modeMenuItem is not null) _modeMenuItem.Checked = _settings.Mode == HudMode.Interactive;
        if (_topmostMenuItem is not null) _topmostMenuItem.Checked = _settings.IsTopmost;
        if (_scopeAllMenuItem is not null) _scopeAllMenuItem.Checked = _settings.Scope == HudScope.All;
        if (_scopeTodayMenuItem is not null) _scopeTodayMenuItem.Checked = _settings.Scope == HudScope.Today;
        if (_opacity70MenuItem is not null) _opacity70MenuItem.Checked = _settings.Opacity == 0.70;
        if (_opacity85MenuItem is not null) _opacity85MenuItem.Checked = _settings.Opacity == 0.85;
        if (_opacity92MenuItem is not null) _opacity92MenuItem.Checked = _settings.Opacity == 0.92;
        if (_opacity100MenuItem is not null) _opacity100MenuItem.Checked = _settings.Opacity == 1.0;
        if (_maxItems5MenuItem is not null) _maxItems5MenuItem.Checked = _settings.MaxItems == 5;
        if (_maxItems8MenuItem is not null) _maxItems8MenuItem.Checked = _settings.MaxItems == 8;
        if (_maxItems12MenuItem is not null) _maxItems12MenuItem.Checked = _settings.MaxItems == 12;
        if (_maxItems20MenuItem is not null) _maxItems20MenuItem.Checked = _settings.MaxItems == 20;
    }

    private void Shutdown()
    {
        _allowWindowClose = true;
        ShutdownMode();
    }

    private static void ShutdownMode()
    {
        CurrentApplication?.Shutdown();
    }

    private static System.Windows.Application? CurrentApplication => System.Windows.Application.Current;
}
