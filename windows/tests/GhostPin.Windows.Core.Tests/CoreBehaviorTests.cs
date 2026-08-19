using System.IO;
using System.Text.Json;
using GhostPin.Windows.App.Platform;
using GhostPin.Windows.Core.Domain;
using GhostPin.Windows.Core.Models;
using GhostPin.Windows.Core.Projection;
using GhostPin.Windows.Core.Serialization;
using GhostPin.Windows.Core.Settings;
using GhostPin.Windows.Core.Storage;

namespace GhostPin.Windows.Core.Tests;

[TestClass]
public sealed class JsonCompatibilityTests
{
    [TestMethod]
    public void ReadsSharedFixtureWithLowercaseEnumsAndUnknownFields()
    {
        var json = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "tasks-cross-language.json"));
        var items = TodoJsonCodec.Deserialize(json);

        Assert.AreEqual(2, items.Count);
        Assert.AreEqual(TodoStatus.Doing, items[0].Status);
        Assert.AreEqual(Priority.High, items[0].Priority);
        Assert.AreEqual("+08:00", items[0].CreatedAt.ToString("zzz"));
        var serialized = TodoJsonCodec.Serialize(items);
        StringAssert.Contains(serialized, "\"status\": \"doing\"");
        using var document = JsonDocument.Parse(serialized);
        Assert.IsFalse(document.RootElement[0].TryGetProperty("isCompleted", out _));
    }

    [TestMethod]
    public void MissingStatusUsesCompletedAtCompatibilityMapping()
    {
        var json = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "tasks-legacy-missing-status.json"));
        var items = TodoJsonCodec.Deserialize(json);

        Assert.AreEqual(TodoStatus.Todo, items[0].Status);
        Assert.AreEqual(TodoStatus.Done, items[1].Status);
        Assert.IsTrue(items[1].IsCompleted);
    }

    [TestMethod]
    public void InvalidKnownEnumFailsRatherThanSilentlyWritingData()
    {
        Assert.ThrowsExactly<System.Text.Json.JsonException>(() => TodoJsonCodec.Deserialize("[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"x\",\"createdAt\":\"2026-08-19T00:00:00Z\",\"status\":\"paused\"}]"));
    }

    [TestMethod]
    public void NullableStringTypeMismatchFailsLikeSwiftDecoder()
    {
        Assert.ThrowsExactly<JsonException>(() => TodoJsonCodec.Deserialize("[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"x\",\"createdAt\":\"2026-08-19T00:00:00Z\",\"description\":123}]"));
    }

    [TestMethod]
    public void WritesUtcSecondPrecisionIso8601WithoutComputedFields()
    {
        var item = new TodoItem(
            "wire",
            new DateTimeOffset(2026, 8, 19, 12, 34, 56, 789, TimeSpan.FromHours(8)),
            status: TodoStatus.Done,
            completedAt: new DateTimeOffset(2026, 8, 19, 13, 2, 3, 456, TimeSpan.FromHours(8)),
            reminderAt: new DateTimeOffset(2026, 8, 20, 1, 2, 3, 999, TimeSpan.FromHours(-5)),
            reminderSentAt: new DateTimeOffset(2026, 8, 20, 7, 8, 9, 111, TimeSpan.Zero),
            dueAt: new DateTimeOffset(2026, 8, 21, 23, 59, 59, 987, TimeSpan.FromHours(9)));

        using var document = JsonDocument.Parse(TodoJsonCodec.Serialize(new[] { item }));
        var root = document.RootElement[0];
        Assert.AreEqual("2026-08-19T04:34:56Z", root.GetProperty("createdAt").GetString());
        Assert.AreEqual("2026-08-19T05:02:03Z", root.GetProperty("completedAt").GetString());
        Assert.AreEqual("2026-08-20T06:02:03Z", root.GetProperty("reminderAt").GetString());
        Assert.AreEqual("2026-08-20T07:08:09Z", root.GetProperty("reminderSentAt").GetString());
        Assert.AreEqual("2026-08-21T14:59:59Z", root.GetProperty("dueAt").GetString());
        Assert.IsFalse(root.TryGetProperty("isCompleted", out _));
    }
}

[TestClass]
public sealed class HudProjectionTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 19, 12, 0, 0, TimeSpan.FromHours(8));

    [TestMethod]
    public void DoingComesFirstAndOverdueSortsAfterOpenTasks()
    {
        var items = new[]
        {
            Item("todo overdue", TodoStatus.Todo, Priority.High, Now.AddHours(-1), Now.AddDays(-1)),
            Item("doing", TodoStatus.Doing, Priority.Medium, Now.AddDays(-2), Now.AddHours(3)),
            Item("todo open", TodoStatus.Todo, Priority.Low, Now.AddHours(-2), Now.AddHours(3)),
            Item("done", TodoStatus.Done, Priority.High, Now.AddHours(-3), Now.AddHours(-1))
        };

        var projection = HudProjection.Project(items, HudScope.All, 10, Now, TimeZoneInfo.CreateCustomTimeZone("+08", TimeSpan.FromHours(8), "+08", "+08"));

        CollectionAssert.AreEqual(new[] { "doing", "todo open", "todo overdue" }, projection.Items.Select(item => item.Title).ToArray());
        Assert.AreEqual(1, projection.DoingItems.Count);
        Assert.AreEqual(2, projection.TodoItems.Count);
    }

    [TestMethod]
    public void TodayScopeAndGlobalLimitHideDoneAndEmptySections()
    {
        var items = new[]
        {
            Item("today doing", TodoStatus.Doing, Priority.Low, Now, null),
            Item("today todo", TodoStatus.Todo, Priority.High, Now.AddMinutes(-1), null),
            Item("future created", TodoStatus.Todo, Priority.High, Now.AddDays(1), null),
            Item("yesterday", TodoStatus.Todo, Priority.High, Now.AddDays(-1), null)
        };

        var projection = HudProjection.Project(items, HudScope.Today, 3, Now, TimeZoneInfo.CreateCustomTimeZone("+08", TimeSpan.FromHours(8), "+08", "+08"));

        CollectionAssert.AreEqual(new[] { "today doing", "future created", "today todo" }, projection.Items.Select(item => item.Title).ToArray());
        Assert.AreEqual(1, projection.DoingItems.Count);
        Assert.AreEqual(2, projection.TodoItems.Count);
    }

    [TestMethod]
    public void GoldenOrderingUsesPriorityDueDateAndCreatedAtThenCapsDoing()
    {
        var sameDue = Now.AddHours(1);
        var items = new[]
        {
            Item("high same due older", TodoStatus.Todo, Priority.High, Now.AddHours(-2), sameDue),
            Item("high same due newer", TodoStatus.Todo, Priority.High, Now.AddHours(-1), sameDue),
            Item("high later due", TodoStatus.Todo, Priority.High, Now.AddHours(-3), Now.AddHours(2)),
            Item("medium due", TodoStatus.Todo, Priority.Medium, Now.AddHours(-4), Now.AddHours(3)),
            Item("low without due", TodoStatus.Todo, Priority.Low, Now.AddHours(-5), null)
        };

        var projection = HudProjection.Project(
            items,
            HudScope.All,
            5,
            Now,
            TimeZoneInfo.CreateCustomTimeZone("+08", TimeSpan.FromHours(8), "+08", "+08"));

        CollectionAssert.AreEqual(
            new[] { "high same due newer", "high same due older", "high later due", "medium due", "low without due" },
            projection.Items.Select(item => item.Title).ToArray());

        var capped = HudProjection.Project(
            new[]
            {
                Item("doing older", TodoStatus.Doing, Priority.Low, Now.AddHours(-2), null),
                Item("doing newer", TodoStatus.Doing, Priority.Low, Now.AddHours(-1), null),
                Item("todo hidden", TodoStatus.Todo, Priority.High, Now, null)
            },
            HudScope.All,
            2,
            Now,
            TimeZoneInfo.CreateCustomTimeZone("+08", TimeSpan.FromHours(8), "+08", "+08"));

        CollectionAssert.AreEqual(new[] { "doing newer", "doing older" }, capped.Items.Select(item => item.Title).ToArray());
        Assert.AreEqual(2, capped.DoingItems.Count);
        Assert.AreEqual(0, capped.TodoItems.Count);
    }

    private static TodoItem Item(string title, TodoStatus status, Priority priority, DateTimeOffset createdAt, DateTimeOffset? dueAt)
    {
        return new TodoItem(title, createdAt, status: status, priority: priority, dueAt: dueAt);
    }
}

[TestClass]
public sealed class StatusAdvanceTests
{
    [TestMethod]
    public void AdvancesTodoThenIgnoresSameItemDuringCooldown()
    {
        var clock = new FakeClock(new DateTimeOffset(2026, 8, 19, 4, 0, 0, TimeSpan.Zero));
        var service = new StatusAdvanceService(clock);
        var item = new TodoItem("x", clock.UtcNow);

        Assert.IsTrue(service.TryAdvance(item, clock.UtcNow, out var first));
        Assert.AreEqual(TodoStatus.Doing, first);
        Assert.IsFalse(service.TryAdvance(item, clock.UtcNow, out _));
        clock.MonotonicMilliseconds += 500;
        Assert.IsTrue(service.TryAdvance(item, clock.UtcNow, out var second));
        Assert.AreEqual(TodoStatus.Done, second);
        Assert.AreEqual(clock.UtcNow, item.CompletedAt);
    }

    [TestMethod]
    public void DoneCannotAdvanceAndInvalidStateDoesNotWriteCompletion()
    {
        var clock = new FakeClock(DateTimeOffset.UtcNow);
        var service = new StatusAdvanceService(clock);
        var item = new TodoItem("done", clock.UtcNow, status: TodoStatus.Done);

        Assert.IsFalse(service.TryAdvance(item, clock.UtcNow, out _));
        Assert.IsNull(item.CompletedAt);
    }

    private sealed class FakeClock(DateTimeOffset now) : IMonotonicClock
    {
        public long MonotonicMilliseconds { get; set; }
        public DateTimeOffset UtcNow { get; set; } = now;
    }
}

[TestClass]
public sealed class StorageTests
{
    [TestMethod]
    public async Task MissingTaskFileLoadsAsEmptySnapshot()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-missing-todos-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            await using var repository = new TodoRepository(path);

            Assert.IsTrue(await repository.LoadAsync());
            Assert.AreEqual(0, repository.Snapshot.Count);
            Assert.IsNull(repository.LastError);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public void ResolvesSeparateFilesAndCreatesMissingDirectory()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-core-");
        try
        {
            var paths = WindowsStoragePaths.Resolve(temporary.FullName);
            Assert.AreEqual(Path.Combine(temporary.FullName, "GhostPin"), paths.RootDirectory);
            Assert.AreNotEqual(paths.TodosFile, paths.SettingsFile);
            paths.EnsureDirectory();
            Assert.IsTrue(Directory.Exists(paths.RootDirectory));
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task RepositoryKeepsLastValidSnapshotWhenFileIsCorrupt()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-repository-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            var item = new TodoItem("valid", DateTimeOffset.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { item }));
            await using var repository = new TodoRepository(path);
            Assert.IsTrue(await repository.LoadAsync());
            await File.WriteAllTextAsync(path, "{");
            Assert.IsFalse(await repository.LoadAsync());
            Assert.AreEqual(item.Id, repository.Snapshot.Single().Id);
            Assert.IsNotNull(repository.LastError);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task RepositorySelfWriteReloadDoesNotRepublishEquivalentSnapshot()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-advance-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            var clock = new FakeClock(DateTimeOffset.UtcNow);
            var item = new TodoItem("advance", clock.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { item }));
            await using var repository = new TodoRepository(path, clock);
            var snapshotEvents = 0;
            repository.SnapshotChanged += (_, _) => snapshotEvents++;
            var updated = await repository.AdvanceStatusAsync(item.Id);
            Assert.IsNotNull(updated);
            Assert.AreEqual(TodoStatus.Doing, updated!.Status);
            Assert.AreEqual(2, snapshotEvents);
            var publishedBeforeWatcherReload = snapshotEvents;
            Assert.IsTrue(await repository.LoadAsync());
            Assert.AreEqual(publishedBeforeWatcherReload, snapshotEvents);
            var saved = TodoJsonCodec.Deserialize(await File.ReadAllTextAsync(path));
            Assert.AreEqual(TodoStatus.Doing, saved.Single().Status);
            Assert.IsNull(saved.Single().CompletedAt);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task MissingTaskUuidDoesNotWriteOrPublish()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-unknown-uuid-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            var item = new TodoItem("existing", DateTimeOffset.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { item }));
            await using var repository = new TodoRepository(path);
            Assert.IsTrue(await repository.LoadAsync());
            var before = await File.ReadAllBytesAsync(path);
            var events = 0;
            repository.SnapshotChanged += (_, _) => events++;

            var updated = await repository.AdvanceStatusAsync(Guid.NewGuid());
            var after = await File.ReadAllBytesAsync(path);

            Assert.IsNull(updated);
            Assert.IsTrue(before.SequenceEqual(after));
            Assert.AreEqual(0, events);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task FailedAdvanceWriteDoesNotLeaveCooldown()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-advance-failure-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            var clock = new FakeClock(DateTimeOffset.UtcNow);
            var item = new TodoItem("advance", clock.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { item }));
            var attempts = 0;

            async Task WriteOnceThenFail(string targetPath, ReadOnlyMemory<byte> content, CancellationToken cancellationToken)
            {
                if (Interlocked.Increment(ref attempts) == 1)
                {
                    throw new IOException("test write failure");
                }

                await AtomicFile.WriteAsync(targetPath, content, cancellationToken);
            }

            await using var repository = new TodoRepository(path, clock, WriteOnceThenFail);
            await Assert.ThrowsExactlyAsync<IOException>(() => repository.AdvanceStatusAsync(item.Id));
            Assert.IsFalse(repository.IsCoolingDown(item.Id));

            var updated = await repository.AdvanceStatusAsync(item.Id);
            Assert.IsNotNull(updated);
            Assert.AreEqual(TodoStatus.Doing, updated!.Status);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task DirectoryWatcherDebouncesAndReloadsAfterAtomicReplacement()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-watcher-");
        try
        {
            var path = Path.Combine(temporary.FullName, "todos.json");
            var initial = new TodoItem("initial", DateTimeOffset.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { initial }));
            var reloads = 0;
            var reloaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var watcher = new TodoFileWatcher(temporary.FullName, _ =>
            {
                Interlocked.Increment(ref reloads);
                reloaded.TrySetResult(true);
                return Task.CompletedTask;
            });
            watcher.Start();
            var replacement = new TodoItem("replacement", DateTimeOffset.UtcNow);
            await AtomicFile.WriteAsync(path, TodoJsonCodec.SerializeUtf8(new[] { replacement }));
            await reloaded.Task.WaitAsync(TimeSpan.FromSeconds(4));
            await Task.Delay(700);
            Assert.AreEqual(1, Volatile.Read(ref reloads));
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    private sealed class FakeClock(DateTimeOffset now) : IMonotonicClock
    {
        public long MonotonicMilliseconds { get; set; }
        public DateTimeOffset UtcNow { get; set; } = now;
    }
}

[TestClass]
public sealed class SettingsTests
{
    [TestMethod]
    public void SerializeAndRestorePreservesUserSettings()
    {
        var settings = new HudSettings
        {
            IsVisible = false,
            Mode = HudMode.Interactive,
            Opacity = 0.7,
            IsTopmost = false,
            Scope = HudScope.Today,
            MaxItems = 12,
            HudModeHotKeyEnabled = true,
            HudModeHotKeyShortcut = HotKeyShortcut.Create(0x47, HotKeyModifiers.Control | HotKeyModifiers.Alt)
        };

        var restored = HudSettingsCodec.Deserialize(HudSettingsCodec.Serialize(settings));

        Assert.IsFalse(restored.IsVisible);
        Assert.AreEqual(HudMode.Interactive, restored.Mode);
        Assert.AreEqual(0.7, restored.Opacity, 0.0001);
        Assert.IsFalse(restored.IsTopmost);
        Assert.AreEqual(HudScope.Today, restored.Scope);
        Assert.AreEqual(12, restored.MaxItems);
        Assert.IsTrue(restored.HudModeHotKeyEnabled);
        Assert.AreEqual("Ctrl+Alt+G", restored.HudModeHotKeyShortcut?.DisplayName);
    }

    [TestMethod]
    public void InvalidFieldsFallBackIndependently()
    {
        var settings = HudSettingsCodec.Deserialize("""
            {
              "isVisible": false,
              "mode": "interactive",
              "opacity": 1.5,
              "isTopmost": false,
              "scope": "today",
              "maxItems": 0,
              "placement": { "logicalWidth": 200, "logicalHeight": 600, "relativeX": -20 }
            }
            """);

        Assert.IsFalse(settings.IsVisible);
        Assert.AreEqual(HudMode.Interactive, settings.Mode);
        Assert.AreEqual(0.92, settings.Opacity, 0.0001);
        Assert.IsFalse(settings.IsTopmost);
        Assert.AreEqual(HudScope.Today, settings.Scope);
        Assert.AreEqual(8, settings.MaxItems);
        Assert.AreEqual(360, settings.Placement.LogicalWidth, 0.0001);
        Assert.AreEqual(600, settings.Placement.LogicalHeight, 0.0001);
        Assert.AreEqual(-20, settings.Placement.RelativeX, 0.0001);
    }

    [TestMethod]
    public void MaxItemsAboveSettingsWindowRangeFallsBackToDefault()
    {
        var settings = HudSettingsCodec.Deserialize("""
            {
              "maxItems": 21
            }
            """);

        Assert.AreEqual(8, settings.MaxItems);
    }

    [TestMethod]
    public void InvalidHotKeyIsDroppedAndCannotRemainEnabled()
    {
        var settings = HudSettingsCodec.Deserialize("""
            {
              "hudModeHotKeyEnabled": true,
              "hudModeHotKeyShortcut": { "virtualKey": 71, "modifiers": 0 }
            }
            """);

        Assert.IsFalse(settings.HudModeHotKeyEnabled);
        Assert.IsNull(settings.HudModeHotKeyShortcut);
    }

    [TestMethod]
    public async Task CorruptSettingsDoNotAffectTasks()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-settings-");
        try
        {
            var path = Path.Combine(temporary.FullName, "settings.json");
            await File.WriteAllTextAsync(path, "not json");
            var repository = new SettingsRepository(path);
            var settings = await repository.LoadAsync();
            Assert.AreEqual(HudMode.Passthrough, settings.Mode);
            Assert.IsNotNull(repository.LastError);
        }
        finally
        {
            temporary.Delete(true);
        }
    }

    [TestMethod]
    public async Task ConcurrentSettingsSavesLeaveNewestSnapshotOnDisk()
    {
        var temporary = Directory.CreateTempSubdirectory("ghostpin-settings-save-");
        try
        {
            var path = Path.Combine(temporary.FullName, "settings.json");
            var firstStarted = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var releaseFirst = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var writes = 0;

            async Task WriteWithDelayedFirstCall(string targetPath, ReadOnlyMemory<byte> content, CancellationToken cancellationToken)
            {
                if (Interlocked.Increment(ref writes) == 1)
                {
                    firstStarted.SetResult(true);
                    await releaseFirst.Task;
                }

                await AtomicFile.WriteAsync(targetPath, content, cancellationToken);
            }

            var repository = new SettingsRepository(path, WriteWithDelayedFirstCall);
            var oldSettings = HudSettings.Default with { MaxItems = 5 };
            var newestSettings = HudSettings.Default with { MaxItems = 12 };
            var oldSave = repository.SaveAsync(oldSettings);
            await firstStarted.Task;
            var newestSave = repository.SaveAsync(newestSettings);
            releaseFirst.SetResult(true);
            await Task.WhenAll(oldSave, newestSave);

            var saved = HudSettingsCodec.Deserialize(await File.ReadAllTextAsync(path));
            Assert.AreEqual(12, saved.MaxItems);
        }
        finally
        {
            temporary.Delete(true);
        }
    }
}

[TestClass]
public sealed class HotKeyShortcutTests
{
    [TestMethod]
    public void RequiresModifierExceptForFunctionKeys()
    {
        Assert.IsNull(HotKeyShortcut.Create(0x47, HotKeyModifiers.None));
        Assert.IsNull(HotKeyShortcut.Create(0x11, HotKeyModifiers.Control));
        Assert.IsNull(HotKeyShortcut.Create(0xA2, HotKeyModifiers.Control));
        Assert.AreEqual("F8", HotKeyShortcut.Create(0x77, HotKeyModifiers.None)?.DisplayName);
    }

    [TestMethod]
    public void NormalizesModifiersAndBuildsStableDisplayName()
    {
        var shortcut = HotKeyShortcut.Create(
            0x47,
            HotKeyModifiers.Control | HotKeyModifiers.Alt | (HotKeyModifiers)0x8000);

        Assert.IsNotNull(shortcut);
        Assert.AreEqual(HotKeyModifiers.Control | HotKeyModifiers.Alt, shortcut.Modifiers);
        Assert.AreEqual("Ctrl+Alt+G", shortcut.DisplayName);
    }
}

[TestClass]
public sealed class WindowPlacementTests
{
    [TestMethod]
    public void RestoresSavedMonitorCoordinatesAndClampsBeyondItsWorkArea()
    {
        var monitor = new WindowWorkArea("DISPLAY1", -1920, -200, 1920, 1080, 144);
        var restored = WindowPlacementCalculator.Restore(new WindowPlacement
        {
            MonitorId = "DISPLAY1",
            RelativeX = 100,
            RelativeY = 50,
            LogicalWidth = 400,
            LogicalHeight = 300,
            Dpi = 96
        }, new[] { monitor });

        Assert.AreEqual(-1770, restored.Left, 0.0001);
        Assert.AreEqual(-125, restored.Top, 0.0001);
        Assert.AreEqual(600, restored.Width, 0.0001);
        Assert.AreEqual(450, restored.Height, 0.0001);

        var clamped = WindowPlacementCalculator.Restore(new WindowPlacement
        {
            MonitorId = "DISPLAY1",
            RelativeX = -900,
            RelativeY = -900,
            LogicalWidth = 5000,
            LogicalHeight = 100
        }, new[] { monitor });

        Assert.AreEqual(-1920, clamped.Left, 0.0001);
        Assert.AreEqual(-200, clamped.Top, 0.0001);
        Assert.AreEqual(1920, clamped.Width, 0.0001);
        Assert.AreEqual(450, clamped.Height, 0.0001);
    }

    [TestMethod]
    public void MissingMonitorFallsBackAndClampsNegativeCoordinates()
    {
        var monitors = new[]
        {
            new WindowWorkArea("\\\\.\\DISPLAY1", -1920, 0, 1920, 1080, 144),
            new WindowWorkArea("\\\\.\\DISPLAY2", 0, 0, 2560, 1440, 192, true)
        };
        var placement = new WindowPlacement
        {
            MonitorId = "disconnected",
            RelativeX = -900,
            RelativeY = -900,
            LogicalWidth = 5000,
            LogicalHeight = 100,
            Dpi = 96
        };

        var restored = WindowPlacementCalculator.Restore(placement, monitors);

        Assert.AreEqual(0, restored.Left, 0.0001);
        Assert.AreEqual(0, restored.Top, 0.0001);
        Assert.AreEqual(2560, restored.Width, 0.0001);
        Assert.AreEqual(600, restored.Height, 0.0001);
    }

    [TestMethod]
    public void CaptureUsesLogicalCoordinatesAtSavedDpi()
    {
        var monitor = new WindowWorkArea("DISPLAY1", -1920, -200, 1920, 1080, 144);
        var saved = WindowPlacementCalculator.Capture(new WindowRect(-1770, -50, 600, 450), monitor);

        Assert.AreEqual(100, saved.RelativeX, 0.0001);
        Assert.AreEqual(100, saved.RelativeY, 0.0001);
        Assert.AreEqual(400, saved.LogicalWidth, 0.0001);
        Assert.AreEqual(300, saved.LogicalHeight, 0.0001);
        Assert.AreEqual(144u, saved.Dpi);
    }
}

[TestClass]
public sealed class PlatformPureFunctionTests
{
    [TestMethod]
    public void TrayIconLoadsBundledMacStatusBarAsset()
    {
        using var icon = TrayIconLoader.Load(new Uri(
            "/GhostPin.Windows.App;component/Assets/GhostPinStatusBar.png",
            UriKind.Relative));

        Assert.AreNotEqual(IntPtr.Zero, icon.Handle);
        Assert.AreEqual(32, icon.Width);
        Assert.AreEqual(32, icon.Height);
    }

    [TestMethod]
    public void HudStylesKeepOnlyExpectedPassthroughBits()
    {
        var current = Win32.WsExAppWindow | Win32.WsExTransparent | Win32.WsExNoActivate;
        var passthrough = Win32.CalculateHudExtendedStyle(current, HudMode.Passthrough);
        var interactive = Win32.CalculateHudExtendedStyle(current, HudMode.Interactive);

        Assert.AreNotEqual(0L, passthrough & Win32.WsExToolWindow);
        Assert.AreNotEqual(0L, passthrough & Win32.WsExLayered);
        Assert.AreNotEqual(0L, passthrough & Win32.WsExTransparent);
        Assert.AreNotEqual(0L, passthrough & Win32.WsExNoActivate);
        Assert.AreEqual(0L, passthrough & Win32.WsExAppWindow);
        Assert.AreNotEqual(0L, interactive & Win32.WsExToolWindow);
        Assert.AreNotEqual(0L, interactive & Win32.WsExLayered);
        Assert.AreEqual(0L, interactive & Win32.WsExTransparent);
        Assert.AreEqual(0L, interactive & Win32.WsExNoActivate);
        Assert.AreEqual(0L, interactive & Win32.WsExAppWindow);
    }

    [TestMethod]
    public void ResizeHitTestCoversEightDirectionsAndClient()
    {
        var window = new System.Windows.Rect(100, 100, 200, 150);
        var points = new[]
        {
            new System.Windows.Point(100, 100),
            new System.Windows.Point(200, 100),
            new System.Windows.Point(300, 100),
            new System.Windows.Point(300, 175),
            new System.Windows.Point(300, 250),
            new System.Windows.Point(200, 250),
            new System.Windows.Point(100, 250),
            new System.Windows.Point(100, 175),
            new System.Windows.Point(200, 175)
        };
        var expected = new[]
        {
            Win32.HtTopLeft,
            Win32.HtTop,
            Win32.HtTopRight,
            Win32.HtRight,
            Win32.HtBottomRight,
            Win32.HtBottom,
            Win32.HtBottomLeft,
            Win32.HtLeft,
            Win32.HtClient
        };

        CollectionAssert.AreEqual(expected, points.Select(point => HudWindowHost.ResizeHitTest(window, point)).ToArray());
    }

    [TestMethod]
    public void SuggestedRectScalesOnlyWhenDpiChanges()
    {
        var physical = new System.Windows.Rect(10, 20, 200, 100);
        var scaled = WindowPlacementService.ConvertSuggestedRect(physical, 96, 144);
        var unchanged = WindowPlacementService.ConvertSuggestedRect(physical, 144, 144);

        Assert.AreEqual(10, scaled.Left, 0.0001);
        Assert.AreEqual(20, scaled.Top, 0.0001);
        Assert.AreEqual(300, scaled.Width, 0.0001);
        Assert.AreEqual(150, scaled.Height, 0.0001);
        Assert.AreEqual(physical, unchanged);
    }
}
