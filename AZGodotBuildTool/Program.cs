namespace AZGodotBuildTool;

internal static class Program
{
    private static readonly string Usage = $"""
        AZGodotBuildTool generate [--ide vs|cmake] [--platform windows|linux|macos] [--arch x64|arm64] [--config debug|release]
        AZGodotBuildTool build|clean|rebuild [--platform windows|linux|macos] [--arch x64|arm64] [--config debug|release]
        Run from a Godot project or any of its subdirectories.
        Godot {GodotApiRange.Supported}. The C++ API follows [application] config/features in project.godot.
        Builds default to the current OS and architecture.
        Windows x64 uses MSVC. Linux and macOS (x64/arm64) use Ninja and a native C++ compiler.
        Generate a foreign CMake project on any host. Build on the matching platform with its SDK.
        In project.godot, [AZGodotBuildTool] tool_path and godot_cpp_path are relative to the project root
        or absolute. Defaults: the current tool and <project>/.build/godot-cpp.
        Declare ordinary GDCLASS types in module headers under Source/<module> or
        addons/<addon>/Source/<module>. The default configuration is debug.
        """;

    private static int Main(string[] args)
    {
        if (args is ["--help"] or ["-h"] or ["build" or "clean" or "rebuild" or "generate", "--help"])
        {
            Console.WriteLine(Usage);
            return 0;
        }

        if (args.Length % 2 != 1 || args[0] is not ("build" or "clean" or "rebuild" or "generate"))
        {
            Console.Error.WriteLine(Usage);
            return 2;
        }

        try
        {
            string command = args[0];
            var (target, ide) = ParseOptions(args);
            if (!target.IsNative && !(command == "generate" && ide == "cmake"))
                throw new InvalidOperationException($"Use generate --ide cmake for {target.Key} on this host; build or clean on {target.Key}.");
            if (ide == "vs" && target.Platform != DesktopPlatform.Windows)
                throw new InvalidOperationException("--ide vs requires Windows. Use --ide cmake for this target.");
            var project = ProjectDiscovery.Find(Environment.CurrentDirectory);
            Directory.CreateDirectory(project.BuildDirectory);
            using var buildLock = new FileStream(Path.Combine(project.BuildDirectory, "build.lock"),
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            Console.WriteLine($"Project: {project.Root} ({target.Configuration}, {target.Key}, Godot API {project.ApiVersion})");
            if (command == "clean")
            {
                Clean(project, target);
                return 0;
            }
            var libraries = ProjectDiscovery.DiscoverLibraries(project);
            int prebuilt = command is "build" or "rebuild"
                ? PrebuiltAddonValidator.Validate(project, libraries, target) : 0;
            if (libraries.Count == 0)
            {
                if (ide == "vs") VisualStudioProjectGenerator.Generate(project, libraries, null, target);
                else if (ide == "cmake") NativeBuilder.GenerateCMake(project, libraries, project.BindingsPath, target);
                else if (command == "rebuild") Clean(project, target);
                Console.WriteLine(prebuilt == 0 ? "No native modules found." : $"Prebuilt extensions ready: {prebuilt} ({target.Feature}).");
                return 0;
            }
            string bindings = target.IsNative ? FindBindings(project) : project.BindingsPath;
            ExtensionManifest.CheckDestinations(libraries);
            RegistrationGenerator.Generate(project, libraries);
            if (ide == "vs")
            {
                VisualStudioProjectGenerator.Generate(project, libraries, bindings, target);
                return 0;
            }
            foreach (var library in libraries) ModuleRulesLoader.Load(project, library, target);
            if (command == "generate")
            {
                NativeBuilder.GenerateCMake(project, libraries, bindings, target);
                return 0;
            }
            if (command == "rebuild") Clean(project, target);
            NativeBuilder.Build(project, libraries, bindings, target);
            ExtensionManifest.Deploy(project, libraries, target);
            return 0;
        }
        catch (Exception e) when (e is InvalidOperationException or IOException or UnauthorizedAccessException
                                     or System.ComponentModel.Win32Exception)
        {
            Console.Error.WriteLine($"AZGodotBuildTool: {e.Message}");
            return 1;
        }
    }

    private static (BuildTarget Target, string? Ide) ParseOptions(string[] args)
    {
        var platform = BuildTarget.HostPlatform;
        string? arch = null, ide = null;
        string config = "Debug";
        for (int i = 1; i < args.Length; i += 2)
        {
            string value = args[i + 1].ToLowerInvariant();
            switch (args[i])
            {
                case "--platform" when value is "windows" or "linux" or "macos":
                    platform = Enum.Parse<DesktopPlatform>(value, true); break;
                case "--arch" when value is "x64" or "x86_64" or "arm64":
                    arch = value == "arm64" ? value : "x86_64"; break;
                case "--config" when value is "debug" or "release":
                    config = value == "debug" ? "Debug" : "Release"; break;
                case "--ide" when args[0] == "generate" && value is ("cmake" or "vs"):
                    ide = value; break;
                default: throw new InvalidOperationException($"Unknown option: {args[i]} {value}. See AZGodotBuildTool --help.");
            }
        }
        arch ??= platform == BuildTarget.HostPlatform ? BuildTarget.HostArch : platform == DesktopPlatform.MacOS ? "arm64" : "x86_64";
        if (platform == DesktopPlatform.Windows && arch != "x86_64")
            throw new InvalidOperationException("The Windows backend currently supports x64.");
        if (args[0] == "generate")
            ide ??= platform == DesktopPlatform.Windows && platform == BuildTarget.HostPlatform ? "vs" : "cmake";
        return (new BuildTarget(platform, arch, config), ide);
    }

    private static void Clean(GodotProject project, BuildTarget target)
    {
        ExtensionManifest.Clean(project, target);
        NativeBuilder.Clean(project, target);
        Console.WriteLine($"Cleaned {target.Key} {target.Configuration}.");
    }

    private static string FindBindings(GodotProject project)
    {
        string bindings = project.BindingsPath;
        if (!File.Exists(Path.Combine(bindings, "CMakeLists.txt")))
            throw new InvalidOperationException($"godot-cpp not found at '{bindings}'. See AZGodotBuildTool --help.");
        string apiFile = $"extension_api-{project.ApiVersion.Replace('.', '-')}.json";
        if (!File.Exists(Path.Combine(bindings, "gdextension", apiFile)))
            throw new InvalidOperationException($"Expected godot-cpp with gdextension/{apiFile} at '{bindings}'.");
        return bindings;
    }
}
