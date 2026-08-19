using GhostPin.Windows.Core.Storage;

namespace GhostPin.Windows.Core.Settings;

/// <summary>settings.json 的加载、逐字段回退与原子保存。</summary>
public sealed class SettingsRepository
{
    private readonly string _filePath;
    private readonly Func<string, ReadOnlyMemory<byte>, CancellationToken, Task> _atomicWrite;
    private readonly SemaphoreSlim _saveGate = new(1, 1);
    private readonly object _saveSync = new();
    private HudSettings _latestSettings = HudSettings.Default;
    private long _latestVersion;

    public SettingsRepository(
        string filePath,
        Func<string, ReadOnlyMemory<byte>, CancellationToken, Task>? atomicWrite = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        _filePath = Path.GetFullPath(filePath);
        _atomicWrite = atomicWrite ?? AtomicFile.WriteAsync;
    }

    public string FilePath => _filePath;
    public Exception? LastError { get; private set; }

    public async Task<HudSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_filePath))
        {
            LastError = null;
            return HudSettings.Default;
        }

        try
        {
            var json = await File.ReadAllTextAsync(_filePath, cancellationToken);
            var settings = HudSettingsCodec.Deserialize(json);
            LastError = null;
            return settings;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or FormatException)
        {
            LastError = error;
            return HudSettings.Default;
        }
    }

    public async Task SaveAsync(HudSettings settings, CancellationToken cancellationToken = default)
    {
        var snapshot = (settings ?? HudSettings.Default).Normalize();
        long requestedVersion;
        lock (_saveSync)
        {
            _latestSettings = snapshot;
            requestedVersion = ++_latestVersion;
        }

        await _saveGate.WaitAsync(cancellationToken);
        try
        {
            while (true)
            {
                HudSettings pendingSettings;
                long pendingVersion;
                lock (_saveSync)
                {
                    pendingSettings = _latestSettings;
                    pendingVersion = _latestVersion;
                }

                var content = System.Text.Encoding.UTF8.GetBytes(HudSettingsCodec.Serialize(pendingSettings));
                await _atomicWrite(_filePath, content, cancellationToken);

                lock (_saveSync)
                {
                    if (pendingVersion == _latestVersion && requestedVersion <= pendingVersion)
                    {
                        return;
                    }
                }
            }
        }
        finally
        {
            _saveGate.Release();
        }
    }
}
