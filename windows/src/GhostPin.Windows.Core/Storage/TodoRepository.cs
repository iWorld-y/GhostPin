using GhostPin.Windows.Core.Domain;
using GhostPin.Windows.Core.Models;
using GhostPin.Windows.Core.Serialization;

namespace GhostPin.Windows.Core.Storage;

public sealed class TodoSnapshotChangedEventArgs(IReadOnlyList<TodoItem> snapshot) : EventArgs
{
    public IReadOnlyList<TodoItem> Snapshot { get; } = snapshot;
}

/// <summary>todos.json 的唯一读写入口，失败时保留最后一次有效快照。</summary>
public sealed class TodoRepository : IAsyncDisposable
{
    private readonly string _filePath;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly StatusAdvanceService _statusAdvance;
    private readonly IMonotonicClock _clock;
    private readonly Func<string, ReadOnlyMemory<byte>, CancellationToken, Task> _atomicWrite;
    private IReadOnlyList<TodoItem> _snapshot = Array.Empty<TodoItem>();
    private string _publishedContent = TodoJsonCodec.Serialize(Array.Empty<TodoItem>());
    private bool _hasLoaded;

    public TodoRepository(
        string filePath,
        IMonotonicClock? clock = null,
        Func<string, ReadOnlyMemory<byte>, CancellationToken, Task>? atomicWrite = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        _filePath = Path.GetFullPath(filePath);
        _clock = clock ?? new SystemMonotonicClock();
        _statusAdvance = new StatusAdvanceService(_clock);
        _atomicWrite = atomicWrite ?? AtomicFile.WriteAsync;
    }

    public string FilePath => _filePath;
    public IReadOnlyList<TodoItem> Snapshot => _snapshot;
    public Exception? LastError { get; private set; }

    public bool IsCoolingDown(Guid id) => _statusAdvance.IsCoolingDown(id);

    public event EventHandler<TodoSnapshotChangedEventArgs>? SnapshotChanged;
    public event Action<Exception>? DiagnosticError;

    public async Task<bool> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return await ReloadUnderLockAsync(cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>按 UUID 重新读取磁盘后推进状态；无效源文件或冷却中的请求不会写盘。</summary>
    public async Task<TodoItem?> AdvanceStatusAsync(Guid id, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!await ReloadUnderLockAsync(cancellationToken))
            {
                return null;
            }

            var current = _snapshot.FirstOrDefault(item => item.Id == id);
            if (current is null)
            {
                return null;
            }

            var updated = current with { };
            if (!_statusAdvance.TryAdvance(updated, _clock.UtcNow, out _))
            {
                return null;
            }

            var nextSnapshot = _snapshot
                .Select(item => item.Id == id ? updated : item)
                .ToArray();
            try
            {
                await SaveSnapshotUnderLockAsync(nextSnapshot, cancellationToken);
            }
            catch
            {
                _statusAdvance.Rollback(id);
                throw;
            }
            PublishIfChanged(nextSnapshot);
            return updated;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        _gate.Dispose();
        await Task.CompletedTask;
    }

    private async Task<bool> ReloadUnderLockAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_filePath))
        {
            LastError = null;
            PublishIfChanged(Array.Empty<TodoItem>());
            _hasLoaded = true;
            return true;
        }

        try
        {
            var json = await File.ReadAllTextAsync(_filePath, cancellationToken);
            var loaded = TodoJsonCodec.Deserialize(json)
                .OrderByDescending(item => item.CreatedAt)
                .ToArray();
            LastError = null;
            PublishIfChanged(loaded);
            _hasLoaded = true;
            return true;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or FormatException)
        {
            LastError = error;
            DiagnosticError?.Invoke(error);
            // 首次无效文件同样使用安全的空快照，但绝不覆盖磁盘。
            if (!_hasLoaded)
            {
                PublishIfChanged(Array.Empty<TodoItem>());
                _hasLoaded = true;
            }
            return false;
        }
    }

    private async Task SaveSnapshotUnderLockAsync(IReadOnlyList<TodoItem> snapshot, CancellationToken cancellationToken)
    {
        await _atomicWrite(_filePath, TodoJsonCodec.SerializeUtf8(snapshot), cancellationToken);
    }

    private void PublishIfChanged(IReadOnlyList<TodoItem> snapshot)
    {
        var immutable = snapshot.Select(item => item with { }).ToArray();
        var content = TodoJsonCodec.Serialize(immutable);
        if (content == _publishedContent && _hasLoaded)
        {
            return;
        }

        _snapshot = immutable;
        _publishedContent = content;
        SnapshotChanged?.Invoke(this, new TodoSnapshotChangedEventArgs(_snapshot));
    }
}
