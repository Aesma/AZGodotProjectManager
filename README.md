# AZGodotBuildTool

[简体中文](README.zh-CN.md)

AZGodotBuildTool builds a Godot project's C++ code and native addons with one command. It discovers modules, runs their optional C# build rules, generates GDExtension class registration, and uses CMake to build and deploy the native libraries. The command line and the generated Visual Studio solution use the same build process.

## AZGodotProjectManager

The desktop project manager lets you create, import and scan Godot projects, open them in your chosen editor, and enable C++ for an individual project.

**Run from source.** From the repository root, build the CLI with `dotnet build AZGodotBuildTool/AZGodotBuildTool.csproj -c Debug`. Open the [project manager's Godot project](AZGodotProjectManager/project.godot) in Godot 4.7.2 and press **F5**.

1. Open **环境设置** (Environment Settings) and select a Godot editor executable. The manager checks its version and accepts Godot 4.7.x stable. For C++ projects, also select a godot-cpp source directory containing `CMakeLists.txt` and `gdextension/extension_api-4-7.json`. If the directory is unsuitable, you can choose another one or select the supported `10.0.0-stable` download. The download starts after you confirm the version and destination.
2. Use **创建** to create a project, **导入** to add a project folder or its `project.godot`, or **扫描** to find projects under a directory. For a new C++ project, check **使用 C++** during creation. Imported projects can also stay as ordinary Godot projects.
3. To enable C++ later, check **启用 C++** in the upper-right corner of the project's own row. This converts only that project, preserves its existing main scene, and runs project generation and the first Debug build. Open **构建输出** for the compiler log. A failed build can be retried from the same row.
4. Double-click a project or use **打开项目** to edit it. **打开原版 Godot** opens the selected editor's own project manager.

**Package for Windows.** Run the [packaging script](AZGodotProjectManager/package_windows.ps1) from the repository root, substituting the path to your local Godot editor.

```powershell
.\AZGodotProjectManager\package_windows.ps1 -Editor 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
```

The script uses the editor's installed Windows Release template. To use a local template file, pass `-ReleaseTemplate 'C:\path\to\windows_release_x86_64.exe'`. Launch `AZGodotProjectManager.exe` from `AZGodotProjectManager/.build/Windows-x64/`. Distribute that whole directory, including the PCK and `BuildTool/`. C++ builds still require the .NET 10 SDK and the native tools listed below.

## Build NativeDemo

The example targets Godot **4.7.2** and the **4.7** C++ API. Install the .NET 10 SDK, CMake 3.21 or newer, Python 3 and the native tools for your host.

| Host | Native tools | Validation |
| --- | --- | --- |
| Windows x64 | MSVC C++ build tools, Windows SDK, Visual Studio CMake generator | Debug and Release builds, standalone Release game |
| Linux x64 / arm64 | Ninja, GCC or Clang, SQLite development headers and library | x64 Debug game and addon exercised in Godot |
| macOS arm64 / x64 | Ninja, Apple Clang, macOS SDK with SQLite | CMake projects generated for both architectures. Native execution is pending. |

1. Place the [godot-cpp 10.0.0-stable source tree](https://github.com/godotengine/godot-cpp/releases/tag/10.0.0-stable) at `examples/NativeDemo/.build/godot-cpp/`, or point `godot_cpp_path` in [project.godot](examples/NativeDemo/project.godot) to an existing checkout. Its root should contain `CMakeLists.txt` and `gdextension/extension_api-4-7.json`.
2. On Windows, supply the following matching x64 [SQLite development files](https://sqlite.org/download.html) under `examples/NativeDemo/`. They are local prerequisites for the example. If the official DLL archive supplies a `.def`, create its import library in an MSVC developer shell with `lib /machine:x64 /name:sqlite3.dll /def:sqlite3.def /out:sqlite3.lib`. On Linux and macOS the example links the system SQLite library.

   ```text
   ThirdParty/SQLite/include/sqlite3.h
   ThirdParty/SQLite/lib/Win64/sqlite3.lib
   ThirdParty/SQLite/bin/Win64/sqlite3.dll
   ```

3. From the repository root, build the tool and run it in the example project.

   ```shell
   dotnet build AZGodotBuildTool/AZGodotBuildTool.csproj -c Debug
   cd examples/NativeDemo
   dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build
   ```

4. Open `examples/NativeDemo/project.godot` with Godot 4.7.2 and press **F5**. The game module queries an in-memory SQLite database and prints `SQLite score: 42`. The addon displays `Hello from LabelStyle!`.

## IDE and command line

Run these commands from `examples/NativeDemo/`. On Windows, the first command creates `NativeDemo.AZGodotBuildTool.sln` for Visual Studio or Rider. Build, Clean and Rebuild in the solution call the tool for the selected configuration. Run Generate again to refresh the IDE's source tree after adding files. Build discovers new sources on each invocation.

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll generate --ide vs
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build --config release
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll --help
```

Use `generate --ide cmake` for a CMake project. For example, `generate --ide cmake --platform macos --arch arm64` can generate macOS project inputs on Windows. Run the native build on the matching OS and architecture. Native Linux and macOS generation also produces a compilation database.

## Module layout

| Path relative to `project.godot` | Role |
| --- | --- |
| `Source/<Module>/` | Game module. Game modules link into one game library. |
| `addons/<addon>/Source/<Module>/` | Addon module. Each native addon produces its own library and descriptor. |
| `<module directory>/<Module>.Build.cs` | Optional rules for module dependencies, include paths, libraries and runtime files. |

The generator registers ordinary header-declared `GDCLASS` types at the Scene initialization level, with base classes before derived classes. Methods, properties and signals are bound in the class's own `_bind_methods()`.

In NativeDemo, [Gameplay](examples/NativeDemo/Source/Gameplay/Gameplay.Build.cs) depends on [GameData](examples/NativeDemo/Source/GameData/GameData.Build.cs), which configures SQLite. Independently, the addon's [DemoLabel](examples/NativeDemo/addons/demo_label/Source/DemoLabel/DemoLabel.Build.cs) module depends on LabelStyle. Only a module's `Public/` headers are visible to dependants. Public dependencies propagate to their consumers. Private dependencies are used when compiling the declaring module.

## Export the Windows example

Build the native libraries with `--config release`. The included [Windows Release preset](examples/NativeDemo/export_presets.cfg) expects the Godot 4.7.2 standard Windows x64 release template at `examples/NativeDemo/.build/export_templates/4.7.2.stable/windows_release_x86_64.exe`. Supply that template locally or select your own copy in the preset. Export using **Project → Export → Windows Release**. Distribute the entire resulting `.build/export/Windows-x64/` folder so the executable can load its PCK and DLLs.
