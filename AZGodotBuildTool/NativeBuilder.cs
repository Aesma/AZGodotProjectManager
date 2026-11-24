using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace AZGodotBuildTool;

internal static class NativeBuilder
{
    public static string StageDirectory(GodotProject project, BuildTarget target) =>
        target.ConfigPath(Path.Combine(project.BuildDirectory, "stage", project.ApiVersion));

    public static string StagedBinary(GodotProject project, NativeLibrary library, BuildTarget target) =>
        Path.Combine(StageDirectory(project, target), library.Target, library.BinaryName(target));

    public static void Build(GodotProject project, List<NativeLibrary> libraries, string bindings, BuildTarget target)
    {
        var build = Configure(project, libraries, bindings, target);
        string[] parallel = Environment.GetEnvironmentVariable("CMAKE_BUILD_PARALLEL_LEVEL") is null ? ["--parallel"] : [];
        RunCMake(project.Root, ["--build", build, "--config", target.Configuration, .. parallel]);
    }

    public static void Clean(GodotProject project, BuildTarget target)
    {
        var build = BuildDirectory(project, target);
        // Let the backend remove its own products, including those from older AZGodotBuildTool builds.
        if ((File.Exists(Path.Combine(build, "AZGodotBuildTool-configured.sha256")) ||
             File.Exists(Path.Combine(build, "azbuild-configured.sha256"))) &&
            File.Exists(Path.Combine(build, "CMakeCache.txt")))
            RunCMake(project.Root, "--build", build, "--config", target.Configuration, "--target", "clean");
    }

    public static string PrepareIde(GodotProject project, List<NativeLibrary> libraries, string bindings, BuildTarget target)
    {
        var build = Configure(project, libraries, bindings, target);
        RunCMake(project.Root, "--build", build, "--config", target.Configuration, "--target", "generate_bindings");
        return build;
    }

    public static void GenerateCMake(GodotProject project, List<NativeLibrary> libraries, string bindings, BuildTarget target)
    {
        var source = WriteProject(project, libraries, bindings, target);
        Console.WriteLine($"CMake project: {Path.Combine(source, "CMakeLists.txt")}");
        if (libraries.Count == 0) return;
        if (!target.IsNative)
        {
            Console.WriteLine($"Configure on {target.Key} to produce the compilation database.");
            return;
        }
        var build = ConfigureTree(project, source, target);
        RunCMake(project.Root, "--build", build, "--config", target.Configuration, "--target", "generate_bindings");
        if (target.Platform != DesktopPlatform.Windows) Console.WriteLine($"Compilation database: {Path.Combine(build, "compile_commands.json")}");
    }

    private static string BuildDirectory(GodotProject project, BuildTarget target) =>
        target.ConfigPath(Path.Combine(project.BuildDirectory, "native", project.ApiVersion));

    private static string Configure(GodotProject project, List<NativeLibrary> libraries, string bindings, BuildTarget target) =>
        ConfigureTree(project, WriteProject(project, libraries, bindings, target), target);

    private static string WriteProject(GodotProject project, List<NativeLibrary> libraries, string bindings, BuildTarget target)
    {
        var source = target.ConfigPath(Path.Combine(project.BuildDirectory, "cmake"));
        string config = target.Configuration;
        var cmake = new StringBuilder();
        string rootPath = Path.GetRelativePath(source, project.Root).Replace('\\', '/');
        cmake.AppendLine("cmake_minimum_required(VERSION 3.21)");
        cmake.AppendLine($"get_filename_component(AZGODOTBUILDTOOL_ROOT \"${{CMAKE_CURRENT_LIST_DIR}}/{rootPath}\" ABSOLUTE)");
        cmake.AppendLine($"set(AZGODOTBUILDTOOL_GODOT_CPP {ProjectPath(bindings)} CACHE PATH \"godot-cpp source directory\")");
        cmake.AppendLine($"set(CMAKE_BUILD_TYPE {config} CACHE STRING \"Build configuration\")");
        if (target.Platform == DesktopPlatform.MacOS)
            cmake.AppendLine($"set(CMAKE_OSX_ARCHITECTURES {target.Architecture})");
        if (target.Platform != DesktopPlatform.Windows) cmake.AppendLine("set(CMAKE_EXPORT_COMPILE_COMMANDS ON)");
        cmake.AppendLine("project(AzNative LANGUAGES CXX)");
        string toolchain = target.Platform switch
        {
            DesktopPlatform.Windows => "CMAKE_SYSTEM_NAME STREQUAL \"Windows\" AND CMAKE_CXX_COMPILER_ID STREQUAL \"MSVC\" AND CMAKE_VS_PLATFORM_NAME STREQUAL \"x64\"",
            DesktopPlatform.Linux => $"CMAKE_SYSTEM_NAME STREQUAL \"Linux\" AND CMAKE_SYSTEM_PROCESSOR MATCHES \"^{(target.Architecture == "arm64" ? "(aarch64|arm64)" : "(x86_64|amd64|AMD64)")}$\"",
            _ => "CMAKE_SYSTEM_NAME STREQUAL \"Darwin\""
        };
        cmake.AppendLine($"if(NOT ({toolchain}))\n    message(FATAL_ERROR \"This project targets {target.Key}. Select its native toolchain.\")\nendif()");
        if (target.Platform == DesktopPlatform.Windows) cmake.AppendLine("set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)");
        cmake.AppendLine($"set(GODOTCPP_API_VERSION {project.ApiVersion} CACHE STRING \"\" FORCE)");
        string template = config == "Debug" ? "template_debug" : "template_release";
        cmake.AppendLine($"set(GODOTCPP_TARGET {template} CACHE STRING \"\" FORCE)");
        if (libraries.Count > 0) cmake.AppendLine("add_subdirectory(\"${AZGODOTBUILDTOOL_GODOT_CPP}\" godot-cpp)");
        foreach (var library in libraries)
        {
            var id = library.Target;
            cmake.AppendLine($"add_library({id} SHARED");
            cmake.AppendLine($"    {ProjectPath(library.RegistrationFile(project))}");
            foreach (var file in library.Sources) cmake.AppendLine($"    {ProjectPath(file)}");
            cmake.AppendLine(")");
            cmake.AppendLine($"target_link_libraries({id} PRIVATE godot::cpp");
            foreach (string file in library.Modules.SelectMany(m => m.Rules.PrivateLibraries.Select(m.ResolvePath)).Distinct())
                cmake.AppendLine($"    {ProjectPath(file)}");
            foreach (string system in library.Modules.SelectMany(m => m.Rules.SystemLibraries).Distinct())
                cmake.AppendLine($"    {Quote(system)}");
            cmake.AppendLine(")");
            cmake.AppendLine($"target_compile_features({id} PRIVATE cxx_std_17)");
            foreach (var module in library.Modules)
                WriteSourceIncludes(cmake, module.Sources, module.IncludeDirectories);
            // This generated translation unit includes the registered headers of every module.
            WriteSourceIncludes(cmake, [library.RegistrationFile(project)],
                library.Modules.SelectMany(m => m.IncludeDirectories).Distinct());
            var binary = StagedBinary(project, library, target);
            var stage = ProjectPath(Path.GetDirectoryName(binary)!);
            var suffix = config.ToUpperInvariant();
            cmake.AppendLine($"set_target_properties({id} PROPERTIES");
            cmake.AppendLine("    PREFIX \"\"");
            if (target.Platform != DesktopPlatform.Windows)
            {
                string rpath = target.Platform == DesktopPlatform.MacOS ? "@loader_path;@executable_path/../Frameworks" : "$ORIGIN";
                cmake.AppendLine($"    BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH \"{rpath}\"");
            }
            cmake.AppendLine($"    OUTPUT_NAME {Quote(Path.GetFileNameWithoutExtension(binary))}");
            cmake.AppendLine($"    LIBRARY_OUTPUT_DIRECTORY_{suffix} {stage}");
            cmake.AppendLine($"    RUNTIME_OUTPUT_DIRECTORY_{suffix} {stage}");
            cmake.AppendLine($"    ARCHIVE_OUTPUT_DIRECTORY_{suffix} {stage}");
            cmake.AppendLine($"    PDB_OUTPUT_DIRECTORY_{suffix} {stage})");
            // Include transitive usage requirements from godot-cpp in the IDE code model.
            if (target.Platform == DesktopPlatform.Windows) cmake.AppendLine($$"""
                file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/{{id}}-$<CONFIG>.index"
                    CONTENT "${CMAKE_VS_PLATFORM_TOOLSET}\n${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}\n$<TARGET_PROPERTY:{{id}},INCLUDE_DIRECTORIES>\n$<TARGET_PROPERTY:{{id}},COMPILE_DEFINITIONS>\n"
                    TARGET {{id}})
                """);
        }
        WriteIfChanged(Path.Combine(source, "CMakeLists.txt"), cmake.ToString());
        return source;

        string ProjectPath(string path)
        {
            if (OperatingSystem.IsWindows() && target.Platform != DesktopPlatform.Windows && path.StartsWith('/')) return Quote(path);
            string relative = Path.GetRelativePath(project.Root, path).Replace('\\', '/');
            if (Path.IsPathRooted(relative) || relative.StartsWith("../", StringComparison.Ordinal)) return Quote(path);
            return "\"${AZGODOTBUILDTOOL_ROOT}/" + relative.Replace("$", "\\$").Replace("\"", "\\\"") + "\"";
        }

        void WriteSourceIncludes(StringBuilder output, List<string> sources, IEnumerable<string> includes)
        {
            if (sources.Count == 0) return;
            output.AppendLine("set_property(SOURCE");
            foreach (string file in sources) output.AppendLine($"    {ProjectPath(file)}");
            output.AppendLine("    APPEND PROPERTY INCLUDE_DIRECTORIES");
            foreach (string include in includes) output.AppendLine($"    {ProjectPath(include)}");
            output.AppendLine(")");
        }
    }

    private static string ConfigureTree(GodotProject project, string source, BuildTarget target)
    {
        var build = BuildDirectory(project, target);
        var definition = File.ReadAllText(Path.Combine(source, "CMakeLists.txt"));
        // Configure before MSBuild opens the solution when source files or whole targets change.
        // Commit the fingerprint only after CMake succeeds so a failed configure is retried.
        var stamp = Path.Combine(build, "AZGodotBuildTool-configured.sha256");
        var fingerprint = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(definition)));
        if (!File.Exists(Path.Combine(build, "CMakeCache.txt")) ||
            !File.Exists(stamp) || File.ReadAllText(stamp) != fingerprint)
        {
            var generator = target.Platform == DesktopPlatform.Windows ? new[] { "-A", "x64" } : ["-G", "Ninja"];
            RunCMake(project.Root, ["-S", source, "-B", build, .. generator, $"-DAZGODOTBUILDTOOL_GODOT_CPP={project.BindingsPath}"]);
            WriteIfChanged(stamp, fingerprint);
        }
        return build;
    }

    private static string Quote(string value)
    {
        string delimiter = "=";
        while (value.Contains("]" + delimiter + "]", StringComparison.Ordinal)) delimiter += "=";
        return $"[{delimiter}[{value.Replace('\\', '/')}]{delimiter}]";
    }

    private static void RunCMake(string directory, params string[] args)
    {
        var info = new ProcessStartInfo("cmake") { WorkingDirectory = directory, UseShellExecute = false };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        info.Environment["PYTHONDONTWRITEBYTECODE"] = "1";
        using var process = Process.Start(info) ?? throw new InvalidOperationException("Could not start CMake.");
        process.WaitForExit();
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"cmake {args[0]} failed with exit code {process.ExitCode}.");
    }

    public static void WriteIfChanged(string path, string contents)
    {
        if (File.Exists(path) && File.ReadAllText(path) == contents) return;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, contents);
            File.Move(temporary, path, true);
        }
        finally { File.Delete(temporary); }
    }
}
