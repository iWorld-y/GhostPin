using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.Core.Domain;

/// <summary>状态推进与单调时钟冷却的可测试实现。</summary>
public sealed class StatusAdvanceService
{
    public static readonly TimeSpan Cooldown = TimeSpan.FromMilliseconds(500);

    private readonly IMonotonicClock _clock;
    private readonly Dictionary<Guid, long> _lastSuccessfulAdvance = new();

    public StatusAdvanceService(IMonotonicClock? clock = null)
    {
        _clock = clock ?? new SystemMonotonicClock();
    }

    public bool TryAdvance(TodoItem item, DateTimeOffset completedAt, out TodoStatus nextStatus)
    {
        ArgumentNullException.ThrowIfNull(item);
        nextStatus = NextStatus(item.Status) ?? item.Status;
        if (NextStatus(item.Status) is null || IsCoolingDown(item.Id))
        {
            return false;
        }

        item.Status = nextStatus;
        item.CompletedAt = nextStatus == TodoStatus.Done ? completedAt : null;
        _lastSuccessfulAdvance[item.Id] = _clock.MonotonicMilliseconds;
        return true;
    }

    public bool IsCoolingDown(Guid id)
    {
        return _lastSuccessfulAdvance.TryGetValue(id, out var timestamp) &&
            _clock.MonotonicMilliseconds - timestamp < (long)Cooldown.TotalMilliseconds;
    }

    public void Rollback(Guid id)
    {
        _lastSuccessfulAdvance.Remove(id);
    }

    public static TodoStatus? NextStatus(TodoStatus status) => status switch
    {
        TodoStatus.Todo => TodoStatus.Doing,
        TodoStatus.Doing => TodoStatus.Done,
        TodoStatus.Done => null,
        _ => null
    };
}

public interface IMonotonicClock
{
    long MonotonicMilliseconds { get; }
    DateTimeOffset UtcNow { get; }
}

public sealed class SystemMonotonicClock : IMonotonicClock
{
    public long MonotonicMilliseconds => Environment.TickCount64;
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}
