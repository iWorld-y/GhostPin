namespace GhostPin.Windows.Core.Storage;

/// <summary>在目标文件同目录完成临时文件写入和替换。</summary>
public static class AtomicFile
{
    public static async Task WriteAsync(string targetPath, ReadOnlyMemory<byte> content, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(targetPath);
        var directory = Path.GetDirectoryName(targetPath) ?? throw new ArgumentException("目标文件必须包含目录。", nameof(targetPath));
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $".{Path.GetFileName(targetPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await using (var stream = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 16 * 1024,
                options: FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(content, cancellationToken);
                await stream.FlushAsync(cancellationToken);
            }

            if (File.Exists(targetPath))
            {
                try
                {
                    File.Replace(temporaryPath, targetPath, destinationBackupFileName: null, ignoreMetadataErrors: true);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Move(temporaryPath, targetPath, overwrite: true);
                }
                catch (IOException)
                {
                    File.Move(temporaryPath, targetPath, overwrite: true);
                }
            }
            else
            {
                File.Move(temporaryPath, targetPath);
            }
        }
        finally
        {
            try
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
            catch (IOException)
            {
                // 清理失败不应覆盖已经完成的原子写入结果。
            }
        }
    }
}
