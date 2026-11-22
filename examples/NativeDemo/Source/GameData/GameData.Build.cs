using System.IO;

public class GameData : ModuleRules
{
    public override void Configure()
    {
        if (Target.Platform != DesktopPlatform.Windows)
        {
            SystemLibraries.Add("sqlite3");
            return;
        }
        var sqlite = Path.Combine(ProjectDirectory, "ThirdParty", "SQLite");
        PrivateIncludePaths.Add(Path.Combine(sqlite, "include"));
        PrivateLibraries.Add(Path.Combine(sqlite, "lib", "Win64", "sqlite3.lib"));
        RuntimeDependencies.Add(Path.Combine(sqlite, "bin", "Win64", "sqlite3.dll"));
    }
}
