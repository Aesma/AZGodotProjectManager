using System.Text;
using System.Text.Json;

namespace AZGodotBuildTool;

internal static class PrebuiltAddonValidator
{
    public static int Validate(GodotProject project, List<NativeLibrary> libraries, BuildTarget target)
    {
        var addons = new DirectoryInfo(Path.Combine(project.Root, "addons"));
        if (!addons.Exists) return 0;

        var comparer = OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
        var sourceManifests = libraries.Select(l => l.Manifest).ToHashSet(comparer);
        string config = target.Configuration.ToLowerInvariant();
        var features = new HashSet<string>(StringComparer.Ordinal)
        {
            target.PlatformName, target.Architecture, config, "pc", "64", "single", "threads",
            "template", "template_" + config, target.Architecture == "arm64" ? "arm" : "x86"
        };
        if (target.Platform == DesktopPlatform.Linux) features.Add("linuxbsd");
        if (target.Platform == DesktopPlatform.MacOS) features.Add("universal");

        int count = 0;
        foreach (var manifest in FindManifests(addons, new HashSet<string>(comparer)))
        {
            if (sourceManifests.Contains(manifest)) continue;
            var relative = Path.GetRelativePath(addons.FullName, manifest).Replace('\\', '/');
            string addon = relative.Contains('/') ? relative[..relative.IndexOf('/')] : Path.GetFileNameWithoutExtension(relative);
            string context = $"addon '{addon}' ({target.Feature}, res://addons/{relative})";
            string? library = SelectLibrary(project.Root, manifest, features);
            if (library is null)
                throw new InvalidOperationException($"{context}: no matching library mapping or autodetected library.");
            if (!File.Exists(library) && !(target.Platform == DesktopPlatform.MacOS &&
                library.EndsWith(".framework", StringComparison.Ordinal) && Directory.Exists(library)))
                throw new InvalidOperationException($"{context}: library file not found: {library}");
            count++;
        }
        return count;
    }

    private static IEnumerable<string> FindManifests(DirectoryInfo folder, HashSet<string> ancestors)
    {
        if (File.Exists(Path.Combine(folder.FullName, ".gdignore")) || File.Exists(Path.Combine(folder.FullName, "project.godot")))
            yield break;
        string location = folder.ResolveLinkTarget(true)?.FullName ?? folder.FullName;
        if (!ancestors.Add(location)) yield break;
        foreach (var entry in folder.EnumerateFileSystemInfos())
        {
            if (entry.Name.StartsWith('.') || entry.Attributes.HasFlag(FileAttributes.Hidden)) continue;
            if (entry is DirectoryInfo child)
            {
                foreach (string path in FindManifests(child, ancestors)) yield return path;
            }
            else if (entry.Extension.Equals(".gdextension", StringComparison.OrdinalIgnoreCase))
                yield return entry.FullName;
        }
        ancestors.Remove(location);
    }

    private static string? SelectLibrary(string root, string manifest, HashSet<string> features)
    {
        string section = "", prefix = "";
        var mappings = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string raw in File.ReadLines(manifest))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line[0] is ';' or '#') continue;
            if (line[0] == '[')
            {
                int close = line.IndexOf(']');
                section = close >= 0 ? line[1..close] : "";
                continue;
            }
            int equals = line.IndexOf('=');
            if (equals < 0) continue;
            string key = line[..equals].Trim().Trim('"');
            if (section != "libraries" && !(section == "configuration" && key == "autodetect_library_prefix")) continue;
            try
            {
                // ConfigFile strings may have a trailing comment, including after a quoted path.
                var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(line[(equals + 1)..]));
                if (!reader.Read() || reader.TokenType != JsonTokenType.String) throw new JsonException();
                string value = reader.GetString()!;
                if (section == "libraries") mappings[key] = value;
                else prefix = value;
            }
            catch (JsonException)
            {
                throw new InvalidOperationException($"{manifest}: expected a quoted library path for '{key}'.");
            }
        }

        string directory = Path.GetDirectoryName(manifest)!;
        string Resolve(string path) => path.StartsWith("res://", StringComparison.Ordinal)
            ? Path.GetFullPath(path[6..], root) : Path.GetFullPath(path, directory);

        // Godot picks the first entry with the highest number of matching tags.
        string? selected = BestMatch(mappings, features);
        if (!string.IsNullOrEmpty(selected)) return Resolve(selected);
        if (prefix.Length == 0) return null;

        string search = Resolve(prefix);
        string folder = Directory.Exists(search) ? search : Path.GetDirectoryName(search)!;
        string stem = folder == search ? "" : Path.GetFileName(search);
        if (!Directory.Exists(folder)) return null;
        var candidates = Directory.EnumerateFiles(folder)
            .Where(file => Path.GetFileName(file).StartsWith(stem, StringComparison.Ordinal))
            .Select(file => KeyValuePair.Create(Path.GetFileNameWithoutExtension(Path.GetFileName(file)[stem.Length..]), file));
        return BestMatch(candidates, features, StringSplitOptions.RemoveEmptyEntries);
    }

    private static string? BestMatch(IEnumerable<KeyValuePair<string, string>> candidates, HashSet<string> features,
        StringSplitOptions options = StringSplitOptions.None)
    {
        string? best = null;
        int bestCount = 0;
        foreach (var (key, value) in candidates)
        {
            var tags = key.Split('.', options);
            if (tags.Length <= bestCount || !tags.All(tag => features.Contains(tag.Trim()))) continue;
            best = value;
            bestCount = tags.Length;
        }
        return best;
    }
}
