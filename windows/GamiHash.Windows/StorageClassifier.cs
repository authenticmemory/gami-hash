using System.IO;
using System.Runtime.InteropServices;

namespace GamiHash.Windows;

internal sealed record StorageClassification(string Kind, string Reason, bool RequiresConsent);

internal static class StorageClassifier
{
    private const uint FileSupportsRemoteStorage = 0x00000100;

    public static StorageClassification Classify(string path)
    {
        try
        {
            var full = Path.GetFullPath(path);
            if (full.StartsWith(@"\\", StringComparison.Ordinal))
                return new("Network/cloud", "UNC network path", true);

            var root = Path.GetPathRoot(full);
            if (string.IsNullOrWhiteSpace(root))
                return new("Cannot determine", "Windows did not expose enough location metadata", true);

            var driveType = GetDriveType(root);
            if (driveType == 4)
                return new("Network/cloud", "mapped network drive", true);

            foreach (var variable in new[] { "OneDrive", "OneDriveCommercial", "OneDriveConsumer" })
            {
                var syncRoot = Environment.GetEnvironmentVariable(variable);
                if (!string.IsNullOrWhiteSpace(syncRoot) && IsWithin(full, syncRoot))
                    return new("Network/cloud", "registered cloud sync folder", true);
            }

            if (GetVolumeInformation(root, null, 0, out _, out _, out var flags, null, 0) &&
                (flags & FileSupportsRemoteStorage) != 0)
                return new("Network/cloud", "volume supports remote storage", true);

            if (driveType == 3)
                return new("Local", "local Windows volume", false);

            return new("Cannot determine", "Windows did not expose enough location metadata", true);
        }
        catch
        {
            return new("Cannot determine", "location metadata could not be read", true);
        }
    }

    private static bool IsWithin(string path, string root)
    {
        var normalizedPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return normalizedPath.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase);
    }

    [DllImport("kernel32.dll", EntryPoint = "GetDriveTypeW", CharSet = CharSet.Unicode)]
    private static extern uint GetDriveType(string rootPathName);

    [DllImport("kernel32.dll", EntryPoint = "GetVolumeInformationW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetVolumeInformation(
        string rootPathName, char[]? volumeNameBuffer, uint volumeNameSize,
        out uint volumeSerialNumber, out uint maximumComponentLength, out uint fileSystemFlags,
        char[]? fileSystemNameBuffer, uint fileSystemNameSize);
}
