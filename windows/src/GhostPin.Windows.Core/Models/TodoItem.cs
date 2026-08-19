using System.Text.Json.Serialization;

namespace GhostPin.Windows.Core.Models;

/// <summary>与 GhostPin todos.json 兼容的任务模型。</summary>
public sealed record class TodoItem
{
    public Guid Id { get; init; }
    public string Title { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; init; }
    public TodoStatus Status { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public DateTimeOffset? ReminderAt { get; set; }
    public DateTimeOffset? ReminderSentAt { get; set; }
    public Priority Priority { get; set; } = Priority.Medium;
    public DateTimeOffset? DueAt { get; set; }
    public string? Description { get; set; }

    [JsonIgnore]
    public bool IsCompleted => Status == TodoStatus.Done;

    public TodoItem()
    {
    }

    public TodoItem(
        string title,
        DateTimeOffset createdAt,
        Guid? id = null,
        TodoStatus? status = null,
        DateTimeOffset? completedAt = null,
        DateTimeOffset? reminderAt = null,
        DateTimeOffset? reminderSentAt = null,
        Priority priority = Priority.Medium,
        DateTimeOffset? dueAt = null,
        string? description = null)
    {
        Id = id ?? Guid.NewGuid();
        Title = title;
        CreatedAt = createdAt;
        CompletedAt = completedAt;
        Status = status ?? (completedAt is null ? TodoStatus.Todo : TodoStatus.Done);
        ReminderAt = reminderAt;
        ReminderSentAt = reminderSentAt;
        Priority = priority;
        DueAt = dueAt;
        Description = description;
    }

    /// <summary>返回任务是否在指定时刻逾期；已完成任务不视为逾期。</summary>
    public bool IsOverdue(DateTimeOffset now)
    {
        return DueAt is not null && !IsCompleted && DueAt.Value < now;
    }
}
