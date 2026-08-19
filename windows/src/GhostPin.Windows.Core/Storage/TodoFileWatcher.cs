namespace GhostPin.Windows.Core.Storage;

/// <summary>目录级任务文件监听器，合并重复事件并在稳定后完整重载。</summary>
public sealed class TodoFileWatcher : IDisposable
{
    private readonly string _directoryPath;
    private readonly string _fileName;
    private readonly Func<CancellationToken, Task> _reload;
    private readonly object _sync = new();
    private CancellationTokenSource _lifetime = new();
    private CancellationTokenSource? _pendingReload;
    private Task? _pendingReloadTask;
    private FileSystemWatcher? _watcher;
    private bool _started;

    public TodoFileWatcher(string directoryPath, Func<CancellationToken, Task> reload, string fileName = "todos.json")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directoryPath);
        ArgumentNullException.ThrowIfNull(reload);
        _directoryPath = Path.GetFullPath(directoryPath);
        _reload = reload;
        _fileName = fileName;
    }

    public TodoFileWatcher(string directoryPath, Func<Task> reload, string fileName = "todos.json")
        : this(directoryPath, _ => reload(), fileName)
    {
    }

    public event Action<Exception>? DiagnosticError;

    public void Start()
    {
        lock (_sync)
        {
            if (_started)
            {
                return;
            }

            Directory.CreateDirectory(_directoryPath);
            _lifetime = new CancellationTokenSource();
            _started = true;
            try
            {
                CreateWatcherUnderLock();
            }
            catch
            {
                _started = false;
                _lifetime.Dispose();
                throw;
            }
        }
    }

    public void Stop()
    {
        lock (_sync)
        {
            if (!_started)
            {
                return;
            }

            _started = false;
            _watcher?.Dispose();
            _watcher = null;
            _pendingReload?.Cancel();
            _pendingReload = null;
            _lifetime.Cancel();
            _lifetime.Dispose();
        }
    }

    public async Task StopAsync()
    {
        Task? pendingTask;
        CancellationTokenSource lifetime;
        lock (_sync)
        {
            if (!_started)
            {
                return;
            }

            _started = false;
            _watcher?.Dispose();
            _watcher = null;
            _pendingReload?.Cancel();
            _pendingReload = null;
            lifetime = _lifetime;
            lifetime.Cancel();
            pendingTask = _pendingReloadTask;
        }

        if (pendingTask is not null)
        {
            try
            {
                await pendingTask;
            }
            catch (OperationCanceledException)
            {
            }
        }
        lifetime.Dispose();
    }

    public void Dispose() => Stop();

    private void CreateWatcherUnderLock()
    {
        var watcher = new FileSystemWatcher(_directoryPath)
        {
            Filter = "*",
            IncludeSubdirectories = false,
            NotifyFilter = NotifyFilters.CreationTime | NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size
        };
        watcher.Created += OnChanged;
        watcher.Changed += OnChanged;
        watcher.Deleted += OnChanged;
        watcher.Renamed += OnRenamed;
        watcher.Error += OnError;
        watcher.EnableRaisingEvents = true;
        _watcher = watcher;
    }

    private void OnChanged(object sender, FileSystemEventArgs args)
    {
        if (IsRelevant(args.Name))
        {
            ScheduleReload();
        }
    }

    private void OnRenamed(object sender, RenamedEventArgs args)
    {
        if (IsRelevant(args.Name) || IsRelevant(args.OldName))
        {
            ScheduleReload();
        }
    }

    private void OnError(object sender, ErrorEventArgs args)
    {
        var error = args.GetException();
        DiagnosticError?.Invoke(error);
        lock (_sync)
        {
            if (!_started)
            {
                return;
            }

            _watcher?.Dispose();
            CreateWatcherUnderLock();
        }
        ScheduleReload();
    }

    private void ScheduleReload()
    {
        CancellationTokenSource pending;
        lock (_sync)
        {
            if (!_started)
            {
                return;
            }

            _pendingReload?.Cancel();
            pending = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            _pendingReload = pending;
            _pendingReloadTask = DebouncedReloadAsync(pending);
        }
    }

    private async Task DebouncedReloadAsync(CancellationTokenSource pending)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(500), pending.Token);
            await _reload(pending.Token);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception error)
        {
            DiagnosticError?.Invoke(error);
        }
        finally
        {
            lock (_sync)
            {
                if (ReferenceEquals(_pendingReload, pending))
                {
                    _pendingReload = null;
                }
                if (_pendingReloadTask is not null && _pendingReloadTask.IsCompleted)
                {
                    _pendingReloadTask = null;
                }
            }
            pending.Dispose();
        }
    }

    private bool IsRelevant(string? name)
    {
        return !string.IsNullOrWhiteSpace(name) && string.Equals(name, _fileName, StringComparison.OrdinalIgnoreCase);
    }
}
