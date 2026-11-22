using System.Diagnostics;
using System.Reflection;
using System.Runtime.Loader;
using System.Xml.Linq;

namespace AZGodotBuildTool;

internal static class ModuleRulesLoader
{
    public static void Load(GodotProject project, NativeLibrary library, BuildTarget target)
    {
        var ruleModules = library.Modules.Where(m => File.Exists(m.RulesFile)).ToArray();
        if (ruleModules.Length > 0)
        {
            var assembly = Compile(project, library, ruleModules);
            foreach (var module in ruleModules)
            {
                var type = assembly.GetTypes().SingleOrDefault(t =>
                    t.Name == module.Name && typeof(ModuleRules).IsAssignableFrom(t));
                if (type is null)
                    throw new InvalidOperationException($"{module.RulesFile}: expected class {module.Name} : ModuleRules.");
                var rules = (ModuleRules)Activator.CreateInstance(type)!;
                rules.ProjectDirectory = project.Root;
                rules.ModuleDirectory = module.Root;
                rules.Target = target;
                rules.Configure();
                module.Rules = rules;
            }
        }

        var byName = library.Modules.ToDictionary(m => m.Name, StringComparer.Ordinal);
        foreach (var module in library.Modules)
        {
            var includes = module.IncludeDirectories;
            includes.Clear();
            includes.Add(module.Root);
            foreach (string directory in new[] { "Public", "Private" }.Select(d => Path.Combine(module.Root, d)))
                if (Directory.Exists(directory)) includes.Add(directory);
            includes.AddRange(module.Rules.PrivateIncludePaths.Select(module.ResolvePath));

            var visited = new HashSet<string>();
            void ImportPublic(string name, NativeModule requester)
            {
                if (!byName.TryGetValue(name, out var dependency))
                    throw new InvalidOperationException($"{requester.RulesFile}: unknown module '{name}' in {library.Name}.");
                if (!visited.Add(name)) return;
                string directory = Path.Combine(dependency.Root, "Public");
                if (Directory.Exists(directory)) includes.Add(directory);
                foreach (string inherited in dependency.Rules.PublicDependencies)
                    ImportPublic(inherited, dependency);
            }
            foreach (string name in module.Rules.PrivateDependencies.Concat(module.Rules.PublicDependencies))
                ImportPublic(name, module);
        }
    }

    private static Assembly Compile(GodotProject project, NativeLibrary library, NativeModule[] modules)
    {
        var folder = Path.Combine(project.BuildDirectory, "rules", BuildTarget.HostPlatform.ToString(), library.Target);
        string name = library.Target + ".Rules";
        string path = Path.Combine(folder, name + ".csproj");
        var definition = new XElement("Project", new XAttribute("Sdk", "Microsoft.NET.Sdk"),
            new XElement("PropertyGroup", new XElement("TargetFramework", "net10.0"),
                new XElement("EnableDefaultCompileItems", "false"), new XElement("ImplicitUsings", "enable"),
                new XElement("NuGetAudit", "false")),
            new XElement("ItemGroup", new XElement("Using", new XAttribute("Include", "AZGodotBuildTool")),
                new XElement("Reference", new XAttribute("Include", "AZGodotBuildTool"),
                    new XElement("HintPath", typeof(ModuleRules).Assembly.Location), new XElement("Private", "false")),
                modules.Select(m => new XElement("Compile", new XAttribute("Include", m.RulesFile)))));
        NativeBuilder.WriteIfChanged(path, definition.ToString());
        var info = new ProcessStartInfo("dotnet") { WorkingDirectory = folder, UseShellExecute = false };
        foreach (string arg in new[] { "build", path, "--nologo", "--verbosity", "quiet", "--configuration", "Release" })
            info.ArgumentList.Add(arg);
        using var process = Process.Start(info) ?? throw new InvalidOperationException("Could not start the .NET SDK.");
        process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException($"Failed to compile {library.Name} module rules.");
        return AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.Combine(folder, "bin", "Release", "net10.0", name + ".dll"));
    }
}
