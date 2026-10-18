using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

namespace GamiHash.Windows;

internal sealed class EngineClient : IAsyncDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly Process _process;
    private readonly SemaphoreSlim _writes = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly Task _reader;
    private int _nextId;

    public event Action<EngineEvent>? EventReceived;

    private EngineClient(Process process)
    {
        _process = process;
        _reader = Task.Run(ReadLoopAsync);
        _ = Task.Run(async () => { while (await _process.StandardError.ReadLineAsync() is not null) { } });
    }

    public static async Task<EngineClient> StartAsync(string executable)
    {
        var process = Process.Start(new ProcessStartInfo(executable, "--native-ui-worker")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        }) ?? throw new InvalidOperationException("The GAMI Hash engine could not be started.");

        var client = new EngineClient(process);
        var hello = await client.CallAsync("hello", new { });
        if (hello.GetProperty("protocol").GetInt32() != 1)
        {
            await client.DisposeAsync();
            throw new InvalidOperationException("The GAMI Hash engine protocol is incompatible.");
        }
        return client;
    }

    public async Task<ResumeInspection> InspectResumeAsync(string output) =>
        Deserialize<ResumeInspection>(await CallAsync("inspect_resume", new { output }));

    public async Task<PreflightResult> PreflightAsync(string root, string output, string mode) =>
        Deserialize<PreflightResult>(await CallAsync("preflight", new { root, output, workers = 2, mode }));

    public async Task StartRunAsync(string root, string output, string mode, bool storageApproved) =>
        _ = await CallAsync("start", new { root, output, workers = 2, mode, storageApproved });

    public async Task CancelAsync() => _ = await CallAsync("cancel", new { });

    private static T Deserialize<T>(JsonElement value) =>
        value.Deserialize<T>(JsonOptions) ?? throw new InvalidOperationException("The engine returned invalid data.");

    private async Task<JsonElement> CallAsync(string method, object payload)
    {
        var id = Interlocked.Increment(ref _nextId).ToString();
        var completion = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_pending.TryAdd(id, completion)) throw new InvalidOperationException("Duplicate engine request identifier.");
        await _writes.WaitAsync();
        try { await _process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { id, method, payload })); }
        catch { _pending.TryRemove(id, out _); throw; }
        finally { _writes.Release(); }
        return await completion.Task;
    }

    private async Task ReadLoopAsync()
    {
        try
        {
            while (await _process.StandardOutput.ReadLineAsync() is { } line)
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.TryGetProperty("event", out var eventValue))
                {
                    EventReceived?.Invoke(Deserialize<EngineEvent>(eventValue));
                    continue;
                }
                var id = root.TryGetProperty("id", out var idValue) ? idValue.GetString() : null;
                if (id is null || !_pending.TryRemove(id, out var completion)) continue;
                if (root.GetProperty("ok").GetBoolean()) completion.SetResult(root.GetProperty("result").Clone());
                else completion.SetException(new InvalidOperationException(root.GetProperty("error").GetString()));
            }
            throw new InvalidOperationException("The GAMI Hash engine stopped unexpectedly.");
        }
        catch (Exception error)
        {
            foreach (var item in _pending)
                if (_pending.TryRemove(item.Key, out var completion)) completion.TrySetException(error);
        }
    }

    public async ValueTask DisposeAsync()
    {
        _process.StandardInput.Close();
        if (!_process.HasExited)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            try { await _process.WaitForExitAsync(timeout.Token); }
            catch (OperationCanceledException) { _process.Kill(entireProcessTree: true); }
        }
        try { await _reader; } catch { }
        _process.Dispose();
        _writes.Dispose();
    }
}

internal sealed record ResumeInspection(bool Resumable, string? Root, string? Output, long Rows, string? Error);
internal sealed record PreflightResult(string Root, string Output, ResumeInspection Resume, bool WillResume);
internal sealed record EngineProgress(int Phase, long FilesDone, long FilesTotal, long BytesDone, long BytesTotal);
internal sealed record EngineResult(long FilesHashed, long FilesResumed, long FilesFailed, long Warnings, long BytesTotal, string Output, string ErrorLog, bool Canceled);
internal sealed record EngineEvent(string Kind, EngineProgress? Progress, EngineResult? Result, string? Error);
