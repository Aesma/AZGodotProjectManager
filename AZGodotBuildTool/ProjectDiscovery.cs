using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AZGodotBuildTool;

internal sealed record GodotApiRange(int Major, int MinMinor, int MaxMinor)
{
    public static GodotApiRange Supported { get; } = Load();
    public bool Contains(Version version) => version.Major == Major && version.Minor >= MinMinor && version.Minor <= MaxMinor;
    public override string ToString() => $"{Major}.{MinMinor}–{Major}.{MaxMinor}";

    private static GodotApiRange Load()
    {
        using var stream = typeof(GodotApiRange).Assembly.GetManifestResourceStream("godot_api_range.json")!;
        return JsonSerializer.Deserialize<GodotApiRange>(stream)!;
    }
}

internal sealed record GodotProject(string Root, string? ToolPath, string BindingsPath, string ApiVersion)
{
    public string BuildDirectory => Path.Combine(Root, ".build");
}

internal sealed record NativeLibrary(string Name, string Target, string Destination, bool IsAddon,
    List<NativeModule> Modules)
{
    public IEnumerable<string> Headers => Modules.SelectMany(module => module.Headers);
    public IEnumerable<string> Sources => Modules.SelectMany(module => module.Sources);
    public static NativeLibrary FromDirectory(string directory, bool addon)
    {
        string name = Path.GetFileName(directory);
        string target = Regex.Replace(name, "[^A-Za-z0-9_]", "_");
        if (char.IsAsciiDigit(target[0])) target = "_" + target;
        return new(name, target, addon ? directory : Path.Combine(directory, "Binaries"), addon, []);
    }

    public string Symbol => $"{Target}_init";
    public string Manifest => Path.Combine(Destination, Name + ".gdextension");
    public string BinaryFolder(BuildTarget target) => target.Platform == DesktopPlatform.Windows && target.Architecture == "x86_64"
        ? (IsAddon ? "bin" : "Win64") : (IsAddon ? "bin/" + target.Key : target.Key);
    public string BinaryName(BuildTarget target) => Name + target.Suffix;
    public string RegistrationFile(GodotProject project) =>
        Path.Combine(project.BuildDirectory, "generated", Target, "register_types.cpp");
}

internal static class ProjectDiscovery
{
    public static GodotProject Find(string start)
    {
        for (var dir = new DirectoryInfo(start); dir is not null; dir = dir.Parent)
        {
            string settings = Path.Combine(dir.FullName, "project.godot");
            if (File.Exists(settings)) return ReadProject(dir.FullName, settings);
        }
        throw new InvalidOperationException($"No project.godot found in '{start}' or its parents.");
    }

    private static GodotProject ReadProject(string root, string settings)
    {
        string? tool = null;
        string bindings = Path.Combine(root, ".build", "godot-cpp");
        string section = "";
        string? apiVersion = null;
        using var file = File.OpenText(settings);
        while (file.ReadLine() is string raw)
        {
            string line = raw.Trim();
            if (line.StartsWith('['))
            {
                section = line.Split(';', 2)[0].TrimEnd();
                continue;
            }
            var pair = line.Split('=', 2, StringSplitOptions.TrimEntries);
            if (pair.Length != 2) continue;
            if (section == "[application]" && pair[0] == "config/features")
                apiVersion = ReadApiVersion(pair[1], file, settings);
            if (section != "[AZGodotBuildTool]" || pair[0] is not ("tool_path" or "godot_cpp_path")) continue;
            try
            {
                // Read just the quoted value. Godot also allows a comment after it.
                var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(pair[1]));
                if (!reader.Read() || reader.TokenType != JsonTokenType.String) throw new JsonException();
                string value = reader.GetString()!;
                if (string.IsNullOrWhiteSpace(value)) throw new JsonException();
                string path = Path.GetFullPath(value, root);
                if (pair[0] == "tool_path") tool = path;
                else bindings = path;
            }
            catch (JsonException)
            {
                throw new InvalidOperationException($"{settings}: [AZGodotBuildTool] {pair[0]} expects a quoted path.");
            }
        }
        if (apiVersion is null)
            throw new InvalidOperationException($"{settings}: [application] config/features must contain a Godot version ({GodotApiRange.Supported}).");
        return new(root, tool, bindings, apiVersion);
    }

    private static string? ReadApiVersion(string value, TextReader file, string settings)
    {
        // A PackedStringArray can span lines. Read only its quoted values, ignoring comments.
        const string tokens = """[;#].*|"(?:\\.|[^"\\])*"|[)\]]""";
        for (string? line = value; line is not null; line = file.ReadLine())
        {
            foreach (Match match in Regex.Matches(line, tokens))
            {
                string token = match.Value;
                if (token is ")" or "]") return null;
                if (token[0] != '"' || !Version.TryParse(token[1..^1], out var version) || version.Revision >= 0) continue;
                if (!GodotApiRange.Supported.Contains(version))
                    throw new InvalidOperationException($"{settings}: Godot {version} is outside the supported range {GodotApiRange.Supported}.");
                return version.ToString(2);
            }
        }
        return null;
    }

    public static List<NativeLibrary> DiscoverLibraries(GodotProject project)
    {
        var result = new List<NativeLibrary>();
        Discover(project.Root, false, result);
        var addons = Path.Combine(project.Root, "addons");
        if (Directory.Exists(addons))
            foreach (string addon in Directory.GetDirectories(addons).Order(StringComparer.Ordinal))
                Discover(addon, true, result);
        return result;
    }

    private static void Discover(string directory, bool addon, List<NativeLibrary> libraries)
    {
        var source = Path.Combine(directory, "Source");
        if (!Directory.Exists(source)) return;
        var modules = Directory.GetDirectories(source).Order(StringComparer.Ordinal).ToArray();
        if (modules.Length == 0) return;
        var library = NativeLibrary.FromDirectory(directory, addon);
        foreach (string directoryPath in modules)
        {
            var module = new NativeModule(directoryPath);
            foreach (string file in Directory.EnumerateFiles(directoryPath, "*", SearchOption.AllDirectories)
                         .Order(StringComparer.Ordinal))
            {
                switch (Path.GetExtension(file).ToLowerInvariant())
                {
                    case ".h": case ".hh": case ".hpp": case ".hxx": module.Headers.Add(file); break;
                    case ".cpp": case ".cc": case ".cxx": module.Sources.Add(file); break;
                }
            }
            library.Modules.Add(module);
        }
        libraries.Add(library);
    }
}
