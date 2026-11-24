# AZGodotProjectManager

[Simplified Chinese](README.zh-CN.md)

AZGodotProjectManager is a desktop app for creating, importing, finding, and opening Godot projects. Each project has its own C++ setting. Enable it to generate an IDE project and build the game's C++ code and native addons together with AZGodotBuildTool.

## Open your first project

1. **Start the manager.** From a packaged Windows build, launch `AZGodotProjectManager.exe`. From a source checkout, import [the manager's Godot project](AZGodotProjectManager/project.godot) into Godot 4.7.2, open it, and press **F5**.
2. **Choose your editor.** Click **Settings**, then browse for the **Godot editor** executable. The manager accepts stable Godot editors from 4.3 through 4.7, including patch releases and shows a dialog if the selected version is unsupported. Hover over the **?** at the right end of either field heading to see supported versions.
3. **Add a project.** **Create** starts a new project. **Import…** accepts a project directory or its `project.godot` file. **Scan…** finds projects under a folder. If prompted about C++ after importing or scanning, choose **Keep as is** to keep the project's current setup.
4. **Open the project.** Double-click its row or select it and click **Open Project**. To launch the chosen editor's own project manager, click **Open Godot**.

The language button in the upper right shows the current language. Use it to switch between English and Simplified Chinese. The manager remembers your choice.

## Enable C++ for a project

C++ builds require the .NET 10 SDK, CMake 3.21 or newer, Python 3, and the native tools for the target platform.

| Target | Native tools | Verified with NativeDemo |
| --- | --- | --- |
| Windows x64 | MSVC C++ build tools, Windows SDK, Visual Studio CMake generator | Debug and Release builds, plus the exported Release game |
| Linux x64 / arm64 | Ninja and GCC or Clang | Game and addon run in Godot on x64 Debug |
| macOS arm64 / x64 | Ninja, Apple Clang, macOS SDK | CMake projects generated for both architectures. Native builds and runs are unverified. |

1. If you run the manager from source, build its C# tool once from the repository root. The Windows package already includes the tool in `BuildTool/`.

   ```shell
   dotnet build AZGodotBuildTool/AZGodotBuildTool.csproj -c Debug
   ```

2. In **Settings**, set **godot-cpp source directory** to the root of a compatible checkout. The supported godot-cpp release, `10.0.0-stable`, includes API snapshots for Godot 4.3 through 4.7. The manager and CLI read the project's `[application] config/features` to select its major and minor version. For example, a 4.3 project requires `CMakeLists.txt` and `gdextension/extension_api-4-3.json`. When you change the project version, rebuild each platform and configuration you distribute. If the selected directory has no supported SDK, you can choose another folder or select a version and destination, then click **Confirm download**.
3. For a new project, check **Use C++ (AZGodotBuildTool)** during creation. For an existing project, check **Enable C++** in the upper-right corner of its row. If the manager detects existing C++ source, the action reads **Set up C++ build**. The checkbox acts on that row's project. After a scan, you can also select individual projects in the conversion dialog.
4. The manager records the tool and godot-cpp paths in the project's `project.godot`, creates a starter module if needed, generates the IDE files, and runs the first Debug build. Converting an existing project preserves its main scene. Open **Build Output** for the compiler log. After a failed build, fix the reported issue and retry from the same row.

## Repository layout

| Directory | What to open |
| --- | --- |
| `AZGodotProjectManager/` | Open [project.godot](AZGodotProjectManager/project.godot) in Godot to work on the desktop UI. [main.gd](AZGodotProjectManager/main.gd) handles the project list, language selection, and build actions. |
| `AZGodotBuildTool/` | Open [AZGodotBuildTool.csproj](AZGodotBuildTool/AZGodotBuildTool.csproj) in Rider or Visual Studio to work on the C# CLI. [Program.cs](AZGodotBuildTool/Program.cs) dispatches project generation, builds, and deployment. |
| `examples/NativeDemo/` | Open [the demo project](examples/NativeDemo/project.godot) in Godot after building its native libraries. [Main.tscn](examples/NativeDemo/Main.tscn) places a game node and an addon label under a built-in `Control`. |

## Build and run NativeDemo

**Prepare the dependencies.** Build the CLI with the `dotnet build` command above. The demo looks for godot-cpp at `examples/NativeDemo/.build/godot-cpp/`. To reuse an existing checkout, set `godot_cpp_path` under `[AZGodotBuildTool]` in the demo's `project.godot`.

SQLite is a dependency of the demo's `GameData` module. On Windows, supply the SQLite header and its matching x64 import library and DLL at these paths relative to `examples/NativeDemo/`. If your SQLite DLL package provides a definition file, create the import library in an MSVC developer shell with `lib /machine:x64 /name:sqlite3.dll /def:sqlite3.def /out:sqlite3.lib`.

```text
ThirdParty/SQLite/include/sqlite3.h
ThirdParty/SQLite/lib/Win64/sqlite3.lib
ThirdParty/SQLite/bin/Win64/sqlite3.dll
```

On Linux, install the SQLite development headers and library. On macOS, the demo uses SQLite from the system SDK.

**Build both native libraries.** From the repository root, run the following commands.

```shell
cd examples/NativeDemo
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build
```

Open the demo in Godot and press **F5**. The game node queries an in-memory SQLite database and prints `SQLite score: 42` in the Output panel. The addon displays `Hello from LabelStyle!` in the game window.

### IDE and command line

From `examples/NativeDemo/` on Windows, generate a solution for Rider or Visual Studio.

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll generate --ide vs
```

Open `NativeDemo.AZGodotBuildTool.sln`. Build, Clean, and Rebuild invoke the same project-level CLI for the selected configuration. Each build picks up new source files. Run `generate` again to show them in the IDE tree.

Use `generate --ide cmake` for a CMake project. You can generate inputs for another platform, for example with `generate --ide cmake --platform macos --arch arm64` on Windows. Compile on a host matching the target OS and architecture. Native Linux and macOS generation also produces `compile_commands.json`.

### Modules and addons

The build tool discovers game modules under `Source/<Module>/` and links them into one game library. Under `addons/<addon>/Source/<Module>/`, the modules of each addon link into that addon's own library. An optional `<Module>.Build.cs` declares dependencies, include paths, link libraries, and runtime files.

- In the game, `Gameplay` declares a private dependency on `GameData` to call its save API. Only `GameData` configures SQLite. [Gameplay rules](examples/NativeDemo/Source/Gameplay/Gameplay.Build.cs) · [GameData rules](examples/NativeDemo/Source/GameData/GameData.Build.cs)
- In the addon, `DemoLabel` depends on `LabelStyle` for its display text. A dependency exposes the module's `Public/` headers. Public dependencies propagate to consumers, while private dependencies apply to the declaring module. [DemoLabel rules](examples/NativeDemo/addons/demo_label/Source/DemoLabel/DemoLabel.Build.cs)

The tool registers ordinary `GDCLASS` types declared in module headers at the scene initialization level, with base classes first. Bind methods, properties, and signals in the class's own `_bind_methods()`. The build deploys the libraries and writes their platform mappings to each `.gdextension` file.

## Package the project manager for Windows

Run the packaging script from the repository root with the path to your Godot 4.7.2 editor.

```powershell
.\AZGodotProjectManager\package_windows.ps1 -Editor 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
```

The script publishes the C# tool and exports the manager with the installed Windows Release template. To use a local template, add `-ReleaseTemplate 'C:\path\to\windows_release_x86_64.exe'`. Distribute the entire `AZGodotProjectManager/.build/Windows-x64/` directory so the executable, PCK, and `BuildTool/` stay together. [Packaging script](AZGodotProjectManager/package_windows.ps1)

## Export the NativeDemo game for Windows

From `examples/NativeDemo/`, build the Release versions of the game and addon.

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build --config release
```

Open the demo in Godot and choose **Project → Export → Windows Release**. The preset expects the Godot 4.7.2 standard Windows x64 Release template at `.build/export_templates/4.7.2.stable/windows_release_x86_64.exe` inside the demo. Place your local template there or select its location in the preset. Distribute the complete `.build/export/Windows-x64/` directory with `NativeDemo.exe`, its PCK, and the DLLs. [Demo export preset](examples/NativeDemo/export_presets.cfg)
