using System.Runtime.InteropServices;

namespace AZGodotBuildTool;

public enum DesktopPlatform { Windows, Linux, MacOS }

public sealed record BuildTarget(DesktopPlatform Platform, string Architecture, string Configuration)
{
    internal static DesktopPlatform HostPlatform => OperatingSystem.IsWindows() ? DesktopPlatform.Windows
        : OperatingSystem.IsLinux() ? DesktopPlatform.Linux
        : OperatingSystem.IsMacOS() ? DesktopPlatform.MacOS
        : throw new InvalidOperationException("AZGodotBuildTool supports Windows, Linux and macOS.");
    internal static string HostArch => RuntimeInformation.ProcessArchitecture switch
    {
        System.Runtime.InteropServices.Architecture.X64 => "x86_64",
        System.Runtime.InteropServices.Architecture.Arm64 => "arm64",
        var other => throw new InvalidOperationException($"Unsupported architecture: {other}")
    };
    internal bool IsNative => Platform == HostPlatform && Architecture == HostArch;
    internal string PlatformName => Platform.ToString().ToLowerInvariant();
    internal string Key => $"{PlatformName}-{Architecture}";
    internal string Feature => $"{PlatformName}.{Configuration.ToLowerInvariant()}.{Architecture}";
    internal string Extension => Platform switch { DesktopPlatform.Windows => ".dll", DesktopPlatform.Linux => ".so", _ => ".dylib" };
    internal string Suffix => "." + Feature + Extension;
    // Keep the existing Win64 tree so clean/rebuild also work with earlier projects.
    internal string ConfigPath(string parent) => Platform == DesktopPlatform.Windows && Architecture == "x86_64"
        ? Path.Combine(parent, Configuration) : Path.Combine(parent, Key, Configuration);
}

public class ModuleRules
{
    public string ProjectDirectory { get; internal set; } = "";
    public string ModuleDirectory { get; internal set; } = "";
    public BuildTarget Target { get; internal set; } = null!;
    public List<string> PrivateDependencies { get; } = [];
    public List<string> PublicDependencies { get; } = [];
    public List<string> PrivateIncludePaths { get; } = [];
    public List<string> PrivateLibraries { get; } = [];
    public List<string> SystemLibraries { get; } = [];
    public List<string> RuntimeDependencies { get; } = [];

    public virtual void Configure() { }
}

internal sealed class NativeModule(string root)
{
    public string Root { get; } = root;
    public string Name => Path.GetFileName(Root);
    public string RulesFile => Path.Combine(Root, Name + ".Build.cs");
    public List<string> Headers { get; } = [];
    public List<string> Sources { get; } = [];
    public ModuleRules Rules { get; set; } = new();
    public List<string> IncludeDirectories { get; } = [];

    public string ResolvePath(string path)
    {
        // A Unix SDK path in a target rule must stay a Unix path when generating on Windows.
        if (OperatingSystem.IsWindows() && path.StartsWith('/') && Rules.Target.Platform != DesktopPlatform.Windows)
            return path;
        return Path.GetFullPath(path, Root);
    }
}
