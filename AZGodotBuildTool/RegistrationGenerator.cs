using System.Text;
using System.Text.RegularExpressions;

namespace AZGodotBuildTool;

internal static class RegistrationGenerator
{
    private sealed record RegisteredClass(string Name, string QualifiedName, string Parent,
        string Header, int Line, NativeLibrary Library)
    {
        public string Location => $"{Header}({Line})";
    }

    // Blanking literals and comments preserves source offsets for diagnostics.
    private static readonly Regex NonCode = new(
        """//[^\n]*|/\*[\s\S]*?\*/|R"(?<delimiter>[^\s()\\]{0,16})\([\s\S]*?\)\k<delimiter>"|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'""");
    private const string Identifier = @"[\p{L}_][\p{L}\p{Nd}_]*";
    private const string TypeName = Identifier + @"(?:\s*::\s*" + Identifier + ")*";
    private static readonly Regex Token = new(
        @"(?m)^[ \t]*\#(?<directive>(?:\\\r?\n|[^\r\n])*)|" +
        @"\bnamespace\s*(?<namespace>" + TypeName + @")?\s*\{|" +
        @"\bGDCLASS\b|[{}]");
    private static readonly Regex Arguments = new(
        @"\G\s*\(\s*(?<name>" + Identifier + @")\s*,\s*(?:::)?(?<parent>" + TypeName + @")\s*\)");

    public static void Generate(GodotProject project, List<NativeLibrary> libraries)
    {
        var all = new Dictionary<string, RegisteredClass>(StringComparer.Ordinal);
        foreach (var library in libraries)
        {
            foreach (var source in library.Sources)
            {
                var localClass = ReadClasses(library, source).FirstOrDefault();
                if (localClass is not null)
                    throw new InvalidOperationException($"{localClass.Location}: declare '{localClass.Name}' in a module header so it can be registered.");
            }
            foreach (var header in library.Headers)
            foreach (var type in ReadClasses(library, header))
            {
                if (!all.TryAdd(type.Name, type))
                    throw new InvalidOperationException(
                        $"{type.Location}: duplicate Godot class '{type.Name}', first declared at {all[type.Name].Location}.");
            }
        }

        foreach (var library in libraries)
        {
            var ordered = new List<RegisteredClass>();
            var visiting = new HashSet<string>();
            var done = new HashSet<string>();
            void Visit(RegisteredClass type)
            {
                if (done.Contains(type.Name)) return;
                if (!visiting.Add(type.Name))
                    throw new InvalidOperationException($"{type.Location}: inheritance cycle at '{type.Name}'.");
                if (all.TryGetValue(type.Parent, out var parent))
                {
                    if (parent.Library != library)
                        throw new InvalidOperationException($"{type.Location}: base '{type.Parent}' is in a different native library.");
                    Visit(parent);
                }
                visiting.Remove(type.Name);
                done.Add(type.Name);
                ordered.Add(type);
            }

            foreach (var type in all.Values.Where(t => t.Library == library)) Visit(type);
            WriteRegistration(project, library, ordered);
        }
    }

    private static IEnumerable<RegisteredClass> ReadClasses(NativeLibrary library, string path)
    {
        var text = File.ReadAllText(path);
        if (!text.Contains("GDCLASS", StringComparison.Ordinal)) yield break;
        var code = NonCode.Replace(text, m => Regex.Replace(m.Value, @"[^\n]", " "));
        var guard = Regex.Match(code, @"\A\s*(?:#\s*pragma\s+once\s*)?#\s*ifndef\s+(\w+)\s*#\s*define\s+\1\b");
        var namespaces = new Stack<string>();
        var conditions = new Stack<bool>();
        foreach (Match token in Token.Matches(code))
        {
            if (token.Groups["directive"].Success)
            {
                string directive = token.Groups["directive"].Value.Trim();
                if (Regex.IsMatch(directive, @"^if(?:def|ndef)?\b"))
                    conditions.Push(guard.Success && token.Index < guard.Length);
                else if (Regex.IsMatch(directive, @"^endif\b") && conditions.Count > 0)
                    conditions.Pop();
                else if (Regex.IsMatch(directive, @"^(?:else|elif)\b") && conditions.Count > 0)
                {
                    conditions.Pop();
                    conditions.Push(false);
                }
            }
            else if (token.Value.EndsWith('{'))
            {
                namespaces.Push(Regex.Replace(token.Groups["namespace"].Value, @"\s+", ""));
            }
            else if (token.Value == "}")
            {
                if (namespaces.Count > 0) namespaces.Pop();
            }
            else
            {
                int line = 1 + code.AsSpan(0, token.Index).Count('\n');
                if (conditions.Contains(false))
                    throw new InvalidOperationException($"{path}({line}): conditional GDCLASS declarations are not supported.");
                var args = Arguments.Match(code, token.Index + token.Length);
                if (!args.Success)
                    throw new InvalidOperationException($"{path}({line}): expected GDCLASS(ClassName, BaseClass).");
                string name = args.Groups["name"].Value;
                string parent = Regex.Replace(args.Groups["parent"].Value, @"\s+", "").Split("::")[^1];
                string qualified = string.Join("::", namespaces.Reverse().Where(n => n.Length != 0).Append(name));
                yield return new(name, "::" + qualified, parent, path, line, library);
            }
        }
    }

    private static void WriteRegistration(GodotProject project, NativeLibrary library, List<RegisteredClass> classes)
    {
        var output = new StringBuilder();
        output.AppendLine("#include <godot_cpp/godot.hpp>");
        output.AppendLine("#include <godot_cpp/core/class_db.hpp>");
        var path = library.RegistrationFile(project);
        foreach (var header in classes.Select(c => c.Header).Distinct())
        {
            var include = Path.GetRelativePath(Path.GetDirectoryName(path)!, header).Replace('\\', '/');
            output.AppendLine($"#include \"{include}\"");
        }
        output.AppendLine("""

            static void initialize(godot::ModuleInitializationLevel level) {
                if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
            """);
        foreach (var type in classes) output.AppendLine($"    GDREGISTER_CLASS({type.QualifiedName});");
        output.AppendLine($$"""
            }

            static void terminate(godot::ModuleInitializationLevel) {}

            extern "C" GDExtensionBool GDE_EXPORT {{library.Symbol}}(
                    GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
                    GDExtensionInitialization *initialization) {
                godot::GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
                init.register_initializer(initialize);
                init.register_terminator(terminate);
                init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
                return init.init();
            }
            """);
        NativeBuilder.WriteIfChanged(path, output.ToString());
    }
}
