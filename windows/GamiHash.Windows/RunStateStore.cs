using System.Text.Json;
using System.IO;

namespace GamiHash.Windows;

internal sealed record SavedRun(string Root, string Output);

internal static class RunStateStore
{
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AuthenticMemory", "GamiHash");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "last-run.json");

    public static SavedRun? Read()
    {
        try { return File.Exists(FilePath) ? JsonSerializer.Deserialize<SavedRun>(File.ReadAllText(FilePath)) : null; }
        catch { return null; }
    }

    public static void Write(string root, string output)
    {
        Directory.CreateDirectory(DirectoryPath);
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(new SavedRun(root, output)));
        File.Move(temporary, FilePath, true);
    }

    public static void Clear()
    {
        try { File.Delete(FilePath); } catch { }
    }
}
