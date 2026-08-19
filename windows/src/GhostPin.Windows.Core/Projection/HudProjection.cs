using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.Core.Projection;

/// <summary>HUD 中已经排序并截断的任务分区。</summary>
public sealed record HudProjectionResult(
    IReadOnlyList<TodoItem> Items,
    IReadOnlyList<TodoItem> DoingItems,
    IReadOnlyList<TodoItem> TodoItems)
{
    public int Count => Items.Count;
    public bool IsEmpty => Items.Count == 0;
}

/// <summary>与 macOS TodoStore 保持一致的 HUD 纯函数投影。</summary>
public static class HudProjection
{
    public static HudProjectionResult Project(
        IEnumerable<TodoItem> source,
        HudScope scope,
        int maxCount,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null)
    {
        ArgumentNullException.ThrowIfNull(source);
        var zone = timeZone ?? TimeZoneInfo.Local;
        var candidates = source.Where(item => !item.IsCompleted && IsInScope(item, scope, now, zone));
        var ordered = candidates
            .OrderBy(item => item.Status == TodoStatus.Doing ? 0 : 1)
            .ThenBy(item => item.IsOverdue(now) ? 1 : 0)
            .ThenByDescending(item => PriorityRank(item.Priority))
            .ThenBy(item => item.DueAt is null ? 1 : 0)
            .ThenBy(item => item.DueAt ?? DateTimeOffset.MaxValue)
            .ThenByDescending(item => item.CreatedAt)
            .Take(Math.Max(maxCount, 0))
            .ToArray();

        return new HudProjectionResult(
            ordered,
            ordered.Where(item => item.Status == TodoStatus.Doing).ToArray(),
            ordered.Where(item => item.Status == TodoStatus.Todo).ToArray());
    }

    public static IReadOnlyList<TodoItem> ProjectItems(
        IEnumerable<TodoItem> source,
        HudScope scope,
        int maxCount,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null)
    {
        return Project(source, scope, maxCount, now, timeZone).Items;
    }

    private static bool IsInScope(TodoItem item, HudScope scope, DateTimeOffset now, TimeZoneInfo zone)
    {
        if (scope == HudScope.All)
        {
            return true;
        }

        var localNow = TimeZoneInfo.ConvertTime(now, zone);
        var localDayStart = DateTime.SpecifyKind(localNow.Date, DateTimeKind.Unspecified);
        var dayStartUtc = TimeZoneInfo.ConvertTimeToUtc(localDayStart, zone);
        return item.CreatedAt >= new DateTimeOffset(dayStartUtc);
    }

    private static int PriorityRank(Priority priority) => priority switch
    {
        Priority.High => 3,
        Priority.Medium => 2,
        Priority.Low => 1,
        _ => 0
    };
}
