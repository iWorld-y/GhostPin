using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.Core.Serialization;

/// <summary>GhostPin 任务 JSON 的稳定编码与兼容解码入口。</summary>
public static class TodoJsonCodec
{
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    public static IReadOnlyList<TodoItem> Deserialize(string json)
    {
        var items = JsonSerializer.Deserialize<List<TodoItem>>(json, Options);
        return items ?? throw new JsonException("任务 JSON 必须是数组。");
    }

    public static string Serialize(IEnumerable<TodoItem> items)
    {
        return JsonSerializer.Serialize(items, Options);
    }

    public static byte[] SerializeUtf8(IEnumerable<TodoItem> items)
    {
        return JsonSerializer.SerializeToUtf8Bytes(items, Options);
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
            WriteIndented = true,
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };
        options.Converters.Add(new TodoItemJsonConverter());
        return options;
    }

    private sealed class TodoItemJsonConverter : JsonConverter<TodoItem>
    {
        public override TodoItem Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var document = JsonDocument.ParseValue(ref reader);
            var root = document.RootElement;

            var id = ReadRequiredGuid(root, "id");
            var title = ReadRequiredString(root, "title");
            var createdAt = ReadRequiredDate(root, "createdAt");
            var completedAt = ReadNullableDate(root, "completedAt");

            var status = root.TryGetProperty("status", out var statusValue) && statusValue.ValueKind != JsonValueKind.Null
                ? statusValue.ValueKind == JsonValueKind.String
                    ? ParseStatus(statusValue.GetString())
                    : throw new JsonException("任务字段 status 无效。")
                : completedAt is null ? TodoStatus.Todo : TodoStatus.Done;
            var priority = root.TryGetProperty("priority", out var priorityValue) && priorityValue.ValueKind != JsonValueKind.Null
                ? priorityValue.ValueKind == JsonValueKind.String
                    ? ParsePriority(priorityValue.GetString())
                    : throw new JsonException("任务字段 priority 无效。")
                : Priority.Medium;

            return new TodoItem(
                title,
                createdAt,
                id,
                status,
                completedAt,
                ReadNullableDate(root, "reminderAt"),
                ReadNullableDate(root, "reminderSentAt"),
                priority,
                ReadNullableDate(root, "dueAt"),
                ReadNullableString(root, "description"));
        }

        public override void Write(Utf8JsonWriter writer, TodoItem value, JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteString("id", value.Id);
            writer.WriteString("title", value.Title);
            writer.WriteString("createdAt", FormatDate(value.CreatedAt));
            writer.WriteString("status", ToWire(value.Status));
            WriteNullableDate(writer, "completedAt", value.CompletedAt);
            WriteNullableDate(writer, "reminderAt", value.ReminderAt);
            WriteNullableDate(writer, "reminderSentAt", value.ReminderSentAt);
            writer.WriteString("priority", ToWire(value.Priority));
            WriteNullableDate(writer, "dueAt", value.DueAt);
            WriteNullableString(writer, "description", value.Description);
            writer.WriteEndObject();
        }

        private static Guid ReadRequiredGuid(JsonElement root, string name)
        {
            if (root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String &&
                Guid.TryParse(value.GetString(), out var result))
            {
                return result;
            }

            throw new JsonException($"任务字段 {name} 缺失或无效。");
        }

        private static string ReadRequiredString(JsonElement root, string name)
        {
            if (root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String)
            {
                return value.GetString() ?? string.Empty;
            }

            throw new JsonException($"任务字段 {name} 缺失或无效。");
        }

        private static string? ReadNullableString(JsonElement root, string name)
        {
            if (!root.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null)
            {
                return null;
            }

            if (value.ValueKind == JsonValueKind.String)
            {
                return value.GetString();
            }

            throw new JsonException($"任务字段 {name} 无效。");
        }

        private static DateTimeOffset ReadRequiredDate(JsonElement root, string name)
        {
            if (root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String &&
                DateTimeOffset.TryParse(value.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var result))
            {
                return result;
            }

            throw new JsonException($"任务字段 {name} 缺失或无效。");
        }

        private static DateTimeOffset? ReadNullableDate(JsonElement root, string name)
        {
            if (!root.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null)
            {
                return null;
            }

            if (value.ValueKind == JsonValueKind.String &&
                DateTimeOffset.TryParse(value.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var result))
            {
                return result;
            }

            throw new JsonException($"任务字段 {name} 无效。");
        }

        private static TodoStatus ParseStatus(string? value)
        {
            return value?.ToLowerInvariant() switch
            {
                "todo" => TodoStatus.Todo,
                "doing" => TodoStatus.Doing,
                "done" => TodoStatus.Done,
                _ => throw new JsonException($"未知任务状态: {value}")
            };
        }

        private static Priority ParsePriority(string? value)
        {
            return value?.ToLowerInvariant() switch
            {
                "high" => Priority.High,
                "medium" => Priority.Medium,
                "low" => Priority.Low,
                _ => throw new JsonException($"未知任务优先级: {value}")
            };
        }

        private static string ToWire(TodoStatus status) => status switch
        {
            TodoStatus.Todo => "todo",
            TodoStatus.Doing => "doing",
            TodoStatus.Done => "done",
            _ => throw new ArgumentOutOfRangeException(nameof(status))
        };

        private static string ToWire(Priority priority) => priority switch
        {
            Priority.High => "high",
            Priority.Medium => "medium",
            Priority.Low => "low",
            _ => throw new ArgumentOutOfRangeException(nameof(priority))
        };

        private static void WriteNullableDate(Utf8JsonWriter writer, string name, DateTimeOffset? value)
        {
            if (value is null)
            {
                writer.WriteNull(name);
            }
            else
            {
                writer.WriteString(name, FormatDate(value.Value));
            }
        }

        private static string FormatDate(DateTimeOffset value)
        {
            return value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
        }

        private static void WriteNullableString(Utf8JsonWriter writer, string name, string? value)
        {
            if (value is null)
            {
                writer.WriteNull(name);
            }
            else
            {
                writer.WriteString(name, value);
            }
        }
    }
}
