using Microsoft.Win32;
using System.Text.Json;

namespace GamiHash.Windows;

internal sealed record SavedRun(string Root, string Output);

internal static class RunStateStore
{
    private const string KeyPath = @"Software\Authentic Memory\GAMI Hash";
    private const string ValueName = "LastRun";

    public static SavedRun? Read()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
            var json = key?.GetValue(ValueName) as string;
            return string.IsNullOrWhiteSpace(json) ? null : JsonSerializer.Deserialize<SavedRun>(json);
        }
        catch { return null; }
    }

    public static void Write(string root, string output)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        key.SetValue(ValueName, JsonSerializer.Serialize(new SavedRun(root, output)), RegistryValueKind.String);
    }

    public static void Clear()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true);
            key?.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        catch { }
    }
}
