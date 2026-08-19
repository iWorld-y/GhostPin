using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using GhostPin.Windows.Core.Models;
using GhostPin.Windows.Core.Projection;

namespace GhostPin.Windows.App.ViewModels;

public sealed class TaskCardViewModel
{
    public TaskCardViewModel(TodoItem item, DateTimeOffset now)
    {
        Item = item;
        Title = item.Title;
        Description = item.Description;
        PriorityText = item.Priority switch
        {
            Priority.High => "高",
            Priority.Medium => "中",
            Priority.Low => "低",
            _ => string.Empty
        };
        DueText = item.DueAt?.ToLocalTime().ToString("g") ?? string.Empty;
        IsOverdue = item.IsOverdue(now);
        Status = item.Status;
    }

    public TodoItem Item { get; }
    public Guid Id => Item.Id;
    public string Title { get; }
    public string? Description { get; }
    public string PriorityText { get; }
    public string DueText { get; }
    public bool HasDescription => !string.IsNullOrWhiteSpace(Description);
    public bool HasDueDate => !string.IsNullOrWhiteSpace(DueText);
    public bool IsOverdue { get; }
    public TodoStatus Status { get; }
}

/// <summary>WPF 仅负责呈现投影结果，不实现排序或 JSON 逻辑。</summary>
public sealed class HudViewModel : INotifyPropertyChanged
{
    private bool _isInteractive;
    private string? _diagnosticMessage;
    private string? _platformDiagnostic;
    private string? _repositoryDiagnostic;
    private string? _advanceMessage;

    public ObservableCollection<TaskCardViewModel> DoingItems { get; } = new();
    public ObservableCollection<TaskCardViewModel> TodoItems { get; } = new();

    public bool IsInteractive
    {
        get => _isInteractive;
        private set
        {
            if (_isInteractive == value) return;
            _isInteractive = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ModeHint));
            OnPropertyChanged(nameof(CloseVisibility));
        }
    }

    public string? DiagnosticMessage
    {
        get => _diagnosticMessage;
        private set
        {
            if (_diagnosticMessage == value) return;
            _diagnosticMessage = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasDiagnosticMessage));
        }
    }

    public int Count => DoingItems.Count + TodoItems.Count;
    public bool IsEmpty => Count == 0;
    public bool HasDoingItems => DoingItems.Count > 0;
    public bool HasTodoItems => TodoItems.Count > 0;
    public bool HasDiagnosticMessage => !string.IsNullOrWhiteSpace(DiagnosticMessage);
    public string? AdvanceMessage
    {
        get => _advanceMessage;
        private set
        {
            if (_advanceMessage == value) return;
            _advanceMessage = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasAdvanceMessage));
        }
    }

    public bool HasAdvanceMessage => !string.IsNullOrWhiteSpace(AdvanceMessage);
    public string ModeHint => IsInteractive ? "交互模式" : "穿透模式";
    public System.Windows.Visibility CloseVisibility => IsInteractive ? System.Windows.Visibility.Visible : System.Windows.Visibility.Collapsed;

    public void Apply(HudProjectionResult result, DateTimeOffset now)
    {
        DoingItems.Clear();
        TodoItems.Clear();
        foreach (var item in result.DoingItems)
        {
            DoingItems.Add(new TaskCardViewModel(item, now));
        }
        foreach (var item in result.TodoItems)
        {
            TodoItems.Add(new TaskCardViewModel(item, now));
        }
        OnPropertyChanged(nameof(Count));
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(HasDoingItems));
        OnPropertyChanged(nameof(HasTodoItems));
    }

    public void SetMode(HudMode mode) => IsInteractive = mode == HudMode.Interactive;

    public void SetDiagnostic(Exception? error)
    {
        _platformDiagnostic = error is null ? null : $"平台调用失败：{error.Message}";
        UpdateDiagnosticMessage();
    }

    public void SetRepositoryDiagnostic(Exception? error)
    {
        _repositoryDiagnostic = error is null ? null : $"任务刷新失败：{error.Message}";
        UpdateDiagnosticMessage();
    }

    public void SetAdvanceMessage(string? message) => AdvanceMessage = message;

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private void UpdateDiagnosticMessage()
    {
        DiagnosticMessage = _platformDiagnostic ?? _repositoryDiagnostic;
    }
}
