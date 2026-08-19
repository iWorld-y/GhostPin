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
    private readonly SettingsWindow _settingsWindow;
    private GlobalHotKeyService? _hotKeyService;
    private HudSettings _settings = HudSettings.Default;
    private HotKeySetupState _hotKeySetupState = HotKeySetupState.Disabled;
    private HotKeySetupState? _hotKeyStateBeforeRecording;
    private string? _hotKeyMessage;
    private System.Windows.Forms.NotifyIcon? _notifyIcon;
    private System.Windows.Forms.ContextMenuStrip? _notifyMenu;
    private System.Drawing.Icon? _trayIcon;
    private System.Windows.Forms.ToolStripMenuItem? _visibilityMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? _modeMenuItem;
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
        _settingsWindow = new SettingsWindow();

        _window.AdvanceRequested += OnAdvanceRequested;
        _window.HideRequested += HideHud;
        _window.Closing += OnWindowClosing;
        _window.LocationChanged += OnWindowGeometryChanged;
        _window.SizeChanged += OnWindowGeometryChanged;
        _todoRepository.SnapshotChanged += OnSnapshotChanged;
        _todoRepository.DiagnosticError += OnRepositoryDiagnosticError;
        _watcher.DiagnosticError += OnDiagnosticError;
        _windowHost.DiagnosticError += OnDiagnosticError;
        _settingsWindow.OpacityChanged += SetHudOpacity;
        _settingsWindow.ScopeChanged += SetScope;
        _settingsWindow.MaxItemsChanged += SetMaxItems;
        _settingsWindow.TopmostChanged += SetTopmost;
        _settingsWindow.HotKeyEnabledChanged += SetHudModeHotKeyEnabled;
        _settingsWindow.HotKeyRecordingStarted += BeginHotKeyRecording;
        _settingsWindow.HotKeyRecordingCancelled += CancelHotKeyRecording;
        _settingsWindow.HotKeyCandidateSubmitted += SubmitHotKeyCandidate;
        _settingsWindow.HotKeyClearRequested += ClearHudModeHotKeyShortcut;
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
        _hotKeyService = new GlobalHotKeyService(_windowHost.Hwnd, ToggleInteractionMode);
        RestoreHotKeyRegistration();
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
        _settingsWindow.CloseForApplicationExit();
        _hotKeyService?.Dispose();
        _hotKeyService = null;
        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }
        _notifyMenu?.Dispose();
        _notifyMenu = null;
        _trayIcon?.Dispose();
        _trayIcon = null;

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
        _settings.MaxItems = Math.Clamp(maxItems, 1, 20);
        RefreshView();
        UpdateMenuState();
        _ = SaveSettingsSafeAsync();
    }

    public void ShowSettings()
    {
        if (_isStopping) return;
        try
        {
            UpdateHotKeyPresentation();
            _settingsWindow.ShowFor(_settings);
        }
        catch (Exception error)
        {
            SetDiagnostic(error);
        }
    }

    public void SetHudModeHotKeyEnabled(bool enabled)
    {
        if (_isStopping) return;
        _hotKeyMessage = null;
        if (!enabled)
        {
            _hotKeyService?.Unregister();
            _settings.HudModeHotKeyEnabled = false;
            _hotKeySetupState = HotKeySetupState.Disabled;
            UpdateHotKeyPresentation();
            _ = SaveSettingsSafeAsync();
            return;
        }

        if (_settings.HudModeHotKeyShortcut is null)
        {
            _hotKeySetupState = HotKeySetupState.PendingConfiguration;
            UpdateHotKeyPresentation();
            return;
        }

        try
        {
            _hotKeyService?.Register(_settings.HudModeHotKeyShortcut);
            _settings.HudModeHotKeyEnabled = true;
            _hotKeySetupState = HotKeySetupState.Registered;
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            _hotKeySetupState = HotKeySetupState.Failure;
            _hotKeyMessage = error.Message;
        }
        UpdateHotKeyPresentation();
    }

    public void ClearHudModeHotKeyShortcut()
    {
        if (_isStopping) return;
        _hotKeyService?.Unregister();
        _settings.HudModeHotKeyEnabled = false;
        _settings.HudModeHotKeyShortcut = null;
        _hotKeySetupState = HotKeySetupState.Disabled;
        _hotKeyMessage = null;
        UpdateHotKeyPresentation();
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

    private void ToggleInteractionMode()
    {
        var nextMode = _settings.Mode == HudMode.Interactive ? HudMode.Passthrough : HudMode.Interactive;
        SetInteractionMode(nextMode);
    }

    private void BeginHotKeyRecording()
    {
        _hotKeyMessage = null;
        _hotKeyStateBeforeRecording = _hotKeySetupState;
        _hotKeyService?.Unregister();
        UpdateHotKeyPresentation();
    }

    private void CancelHotKeyRecording()
    {
        if (_hotKeyStateBeforeRecording is not { } previous)
        {
            return;
        }

        _hotKeyStateBeforeRecording = null;
        if (previous == HotKeySetupState.Registered)
        {
            RestoreHotKeyRegistration();
        }
        else
        {
            _hotKeySetupState = previous;
            UpdateHotKeyPresentation();
        }
    }

    private void SubmitHotKeyCandidate(HotKeyShortcut candidate)
    {
        _hotKeyStateBeforeRecording = null;
        var previousShortcut = _settings.HudModeHotKeyShortcut;
        var wasEnabled = _settings.HudModeHotKeyEnabled;
        try
        {
            _hotKeyService?.Register(candidate);
            _settings.HudModeHotKeyShortcut = candidate;
            _settings.HudModeHotKeyEnabled = true;
            _hotKeySetupState = HotKeySetupState.Registered;
            _hotKeyMessage = null;
            _ = SaveSettingsSafeAsync();
        }
        catch (Exception error)
        {
            RestoreFailedHotKeyCandidate(candidate, error, previousShortcut, wasEnabled);
        }
        UpdateHotKeyPresentation();
    }

    private void RestoreFailedHotKeyCandidate(
        HotKeyShortcut candidate,
        Exception error,
        HotKeyShortcut? previousShortcut,
        bool wasEnabled)
    {
        if (wasEnabled && previousShortcut is not null)
        {
            try
            {
                _hotKeyService?.Register(previousShortcut);
                _hotKeySetupState = HotKeySetupState.Registered;
                _hotKeyMessage = $"“{candidate.DisplayName}”不可用（{error.Message}），已恢复原快捷键。";
            }
            catch
            {
                _hotKeySetupState = HotKeySetupState.Failure;
                _hotKeyMessage = $"“{candidate.DisplayName}”不可用（{error.Message}），且原快捷键恢复失败。";
            }
            return;
        }

        _hotKeySetupState = HotKeySetupState.Failure;
        _hotKeyMessage = error.Message;
    }

    private void RestoreHotKeyRegistration()
    {
        if (!_settings.HudModeHotKeyEnabled || _settings.HudModeHotKeyShortcut is null)
        {
            _hotKeySetupState = _settings.HudModeHotKeyEnabled
                ? HotKeySetupState.PendingConfiguration
                : HotKeySetupState.Disabled;
            UpdateHotKeyPresentation();
            return;
        }
        if (_hotKeyService?.RegisteredShortcut == _settings.HudModeHotKeyShortcut)
        {
            _hotKeySetupState = HotKeySetupState.Registered;
            UpdateHotKeyPresentation();
            return;
        }

        try
        {
            _hotKeyService?.Register(_settings.HudModeHotKeyShortcut);
            _hotKeySetupState = HotKeySetupState.Registered;
            _hotKeyMessage = null;
        }
        catch (Exception error)
        {
            _hotKeySetupState = HotKeySetupState.Failure;
            _hotKeyMessage = error.Message;
        }
        UpdateHotKeyPresentation();
    }

    private void UpdateHotKeyPresentation()
    {
        var toggleOn = _hotKeySetupState is HotKeySetupState.PendingConfiguration or HotKeySetupState.Registered ||
            _hotKeySetupState == HotKeySetupState.Failure && _settings.HudModeHotKeyEnabled;
        _settingsWindow.ApplyHotKeyState(
            toggleOn,
            _settings.HudModeHotKeyShortcut,
            _hotKeySetupState,
            _hotKeyMessage);
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
        var settingsItem = new System.Windows.Forms.ToolStripMenuItem("设置…");
        settingsItem.Click += (_, _) => ShowSettings();
        var exitItem = new System.Windows.Forms.ToolStripMenuItem("退出 GhostPin");
        exitItem.Click += async (_, _) => await ExitAsync();
        menu.Items.Add(_visibilityMenuItem);
        menu.Items.Add(_modeMenuItem);
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(settingsItem);
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(exitItem);

        var icon = TrayIconLoader.Load(new Uri(
            "/GhostPin.Windows.App;component/Assets/GhostPinStatusBar.png",
            UriKind.Relative));
        var notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = icon,
            Text = "GhostPin",
            ContextMenuStrip = menu
        };
        try
        {
            notifyIcon.Visible = true;
            _trayIcon = icon;
            _notifyMenu = menu;
            _notifyIcon = notifyIcon;
        }
        catch
        {
            notifyIcon.Dispose();
            menu.Dispose();
            icon.Dispose();
            throw;
        }
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
        _settingsWindow.ApplySettings(_settings);
        UpdateHotKeyPresentation();
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
