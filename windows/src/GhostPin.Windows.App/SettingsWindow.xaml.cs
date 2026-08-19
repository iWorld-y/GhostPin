using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using GhostPin.Windows.Core.Models;
using GhostPin.Windows.Core.Settings;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace GhostPin.Windows.App;

public enum HotKeySetupState
{
    Disabled,
    PendingConfiguration,
    Registered,
    Failure
}

/// <summary>集中编辑 Windows HUD 偏好和全局交互快捷键。</summary>
public partial class SettingsWindow : Window
{
    private static readonly Brush SecondaryBrush = new SolidColorBrush(Color.FromRgb(105, 112, 105));
    private static readonly Brush NoticeBrush = new SolidColorBrush(Color.FromRgb(196, 123, 22));
    private static readonly Brush ErrorBrush = new SolidColorBrush(Color.FromRgb(186, 54, 54));

    private bool _isApplying;
    private bool _allowClose;
    private bool _isRecording;
    private bool _hotKeyToggleOn;
    private int _maxItems = HudSettings.Default.MaxItems;

    public SettingsWindow()
    {
        InitializeComponent();
        OpacitySlider.ValueChanged += (_, _) => OnOpacityChanged();
        ScopeComboBox.SelectionChanged += (_, _) => OnScopeChanged();
        DecreaseMaxItemsButton.Click += (_, _) => SetMaxItems(_maxItems - 1, notify: true);
        IncreaseMaxItemsButton.Click += (_, _) => SetMaxItems(_maxItems + 1, notify: true);
        TopmostCheckBox.Checked += (_, _) => OnTopmostChanged(true);
        TopmostCheckBox.Unchecked += (_, _) => OnTopmostChanged(false);
        HotKeyEnabledCheckBox.Checked += (_, _) => OnHotKeyEnabledChanged(true);
        HotKeyEnabledCheckBox.Unchecked += (_, _) => OnHotKeyEnabledChanged(false);
        RecordHotKeyButton.Click += (_, _) => BeginHotKeyRecording();
        ClearHotKeyButton.Click += (_, _) => HotKeyClearRequested?.Invoke();
        Closing += OnClosing;
    }

    public event Action<double>? OpacityChanged;
    public event Action<HudScope>? ScopeChanged;
    public event Action<int>? MaxItemsChanged;
    public event Action<bool>? TopmostChanged;
    public event Action<bool>? HotKeyEnabledChanged;
    public event Action? HotKeyRecordingStarted;
    public event Action? HotKeyRecordingCancelled;
    public event Action<HotKeyShortcut>? HotKeyCandidateSubmitted;
    public event Action? HotKeyClearRequested;

    public void ApplySettings(HudSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        _isApplying = true;
        try
        {
            OpacitySlider.Value = settings.Opacity;
            OpacityValueText.Text = $"{Math.Round(settings.Opacity * 100):0}%";
            ScopeComboBox.SelectedIndex = settings.Scope == HudScope.Today ? 1 : 0;
            SetMaxItems(settings.MaxItems, notify: false);
            TopmostCheckBox.IsChecked = settings.IsTopmost;
        }
        finally
        {
            _isApplying = false;
        }
    }

    public void ApplyHotKeyState(
        bool toggleOn,
        HotKeyShortcut? shortcut,
        HotKeySetupState state,
        string? message)
    {
        _hotKeyToggleOn = toggleOn;
        _isApplying = true;
        try
        {
            HotKeyEnabledCheckBox.IsChecked = toggleOn;
        }
        finally
        {
            _isApplying = false;
        }

        HotKeyValueText.Text = shortcut?.DisplayName ?? "未设置";
        HotKeyEnabledCheckBox.IsEnabled = !_isRecording;
        RecordHotKeyButton.IsEnabled = toggleOn && !_isRecording;
        RecordHotKeyButton.Content = _isRecording ? "正在录制…" : "录制快捷键";
        ClearHotKeyButton.Visibility = shortcut is not null && !_isRecording ? Visibility.Visible : Visibility.Collapsed;

        if (_isRecording)
        {
            ShowHotKeyStatus("请按下快捷键组合，Esc 取消。", NoticeBrush);
            return;
        }
        if (!string.IsNullOrWhiteSpace(message))
        {
            ShowHotKeyStatus(message, state == HotKeySetupState.Failure ? ErrorBrush : NoticeBrush);
            return;
        }

        switch (state)
        {
            case HotKeySetupState.Disabled when shortcut is not null:
                ShowHotKeyStatus("开关已关闭，快捷键停止响应，配置已保留。", SecondaryBrush);
                break;
            case HotKeySetupState.PendingConfiguration:
                ShowHotKeyStatus("开关已打开，请录制快捷键；录制成功并注册后才会保存与生效。", NoticeBrush);
                break;
            case HotKeySetupState.Registered:
                ShowHotKeyStatus("GhostPin 已注册该快捷键；若其他软件同时响应，请更换组合。", SecondaryBrush);
                break;
            case HotKeySetupState.Failure:
                ShowHotKeyStatus("快捷键注册失败，请换一个组合。", ErrorBrush);
                break;
            default:
                ShowHotKeyStatus(string.Empty, SecondaryBrush);
                break;
        }
    }

    public void ShowFor(HudSettings settings)
    {
        ApplySettings(settings);
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    public void CloseForApplicationExit()
    {
        _allowClose = true;
        Close();
    }

    private void OnOpacityChanged()
    {
        OpacityValueText.Text = $"{Math.Round(OpacitySlider.Value * 100):0}%";
        if (!_isApplying) OpacityChanged?.Invoke(OpacitySlider.Value);
    }

    private void OnScopeChanged()
    {
        if (!_isApplying && ScopeComboBox.SelectedIndex >= 0)
        {
            ScopeChanged?.Invoke(ScopeComboBox.SelectedIndex == 1 ? HudScope.Today : HudScope.All);
        }
    }

    private void SetMaxItems(int value, bool notify)
    {
        _maxItems = Math.Clamp(value, 1, 20);
        MaxItemsValueText.Text = $"{_maxItems} 条";
        DecreaseMaxItemsButton.IsEnabled = _maxItems > 1;
        IncreaseMaxItemsButton.IsEnabled = _maxItems < 20;
        if (notify && !_isApplying) MaxItemsChanged?.Invoke(_maxItems);
    }

    private void OnTopmostChanged(bool isTopmost)
    {
        if (!_isApplying) TopmostChanged?.Invoke(isTopmost);
    }

    private void OnHotKeyEnabledChanged(bool enabled)
    {
        if (!_isApplying) HotKeyEnabledChanged?.Invoke(enabled);
    }

    private void BeginHotKeyRecording()
    {
        if (_isRecording || !_hotKeyToggleOn)
        {
            return;
        }

        _isRecording = true;
        HotKeyEnabledCheckBox.IsEnabled = false;
        RecordHotKeyButton.IsEnabled = false;
        RecordHotKeyButton.Content = "正在录制…";
        ClearHotKeyButton.Visibility = Visibility.Collapsed;
        ShowHotKeyStatus("请按下快捷键组合，Esc 取消。", NoticeBrush);
        Activate();
        Focus();
        HotKeyRecordingStarted?.Invoke();
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs args)
    {
        if (!_isRecording)
        {
            return;
        }

        args.Handled = true;
        var key = args.Key == Key.System ? args.SystemKey : args.Key;
        if (key == Key.Escape)
        {
            CancelHotKeyRecording();
            return;
        }

        var virtualKey = KeyInterop.VirtualKeyFromKey(key);
        if (HotKeyShortcut.IsModifierKey(virtualKey))
        {
            return;
        }

        var candidate = HotKeyShortcut.Create(virtualKey, ReadModifiers());
        if (candidate is null)
        {
            ShowHotKeyStatus("不符合规则：请包含 Ctrl、Alt、Shift 或 Win 修饰键，或使用 F1–F20 功能键。", ErrorBrush);
            return;
        }

        _isRecording = false;
        HotKeyCandidateSubmitted?.Invoke(candidate);
    }

    private static HotKeyModifiers ReadModifiers()
    {
        var keyboardModifiers = Keyboard.Modifiers;
        var modifiers = HotKeyModifiers.None;
        if (keyboardModifiers.HasFlag(ModifierKeys.Control)) modifiers |= HotKeyModifiers.Control;
        if (keyboardModifiers.HasFlag(ModifierKeys.Alt)) modifiers |= HotKeyModifiers.Alt;
        if (keyboardModifiers.HasFlag(ModifierKeys.Shift)) modifiers |= HotKeyModifiers.Shift;
        if (keyboardModifiers.HasFlag(ModifierKeys.Windows)) modifiers |= HotKeyModifiers.Windows;
        return modifiers;
    }

    private void CancelHotKeyRecording()
    {
        if (!_isRecording)
        {
            return;
        }

        _isRecording = false;
        HotKeyRecordingCancelled?.Invoke();
    }

    private void ShowHotKeyStatus(string message, Brush brush)
    {
        HotKeyStatusText.Text = message;
        HotKeyStatusText.Foreground = brush;
    }

    private void OnSettingsTabChanged(object sender, SelectionChangedEventArgs args)
    {
        if (_isRecording && SettingsTabs.SelectedIndex != 1)
        {
            CancelHotKeyRecording();
        }
    }

    private void OnClosing(object? sender, CancelEventArgs args)
    {
        if (_allowClose)
        {
            return;
        }

        CancelHotKeyRecording();
        args.Cancel = true;
        Hide();
    }
}
