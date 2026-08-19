namespace GhostPin.Windows.Core.Storage;

/// <summary>Windows 任务与 HUD 设置的本地文件位置。</summary>
public sealed record WindowsStoragePaths(string RootDirectory, string TodosFile, string SettingsFile)
{
    public static WindowsStoragePaths Resolve(string? localAppDataRoot = null)
    {
        var baseDirectory = localAppDataRoot;
        if (string.IsNullOrWhiteSpace(baseDirectory))
        {
            baseDirectory = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        }

        if (string.IsNullOrWhiteSpace(baseDirectory))
        {
            throw new InvalidOperationException("无法解析 Windows LocalAppData 目录。");
        }

        var root = Path.Combine(baseDirectory, "GhostPin");
        return FromRootDirectory(root);
    }

    public static WindowsStoragePaths FromRootDirectory(string rootDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rootDirectory);
        return new WindowsStoragePaths(
            Path.GetFullPath(rootDirectory),
            Path.Combine(rootDirectory, "todos.json"),
            Path.Combine(rootDirectory, "settings.json"));
    }

    public DirectoryInfo EnsureDirectory()
    {
        return Directory.CreateDirectory(RootDirectory);
    }
}
