# AZGodotBuildTool

[English](README.md)

AZGodotBuildTool 用一条命令构建整个 Godot 项目的 C++ 代码和原生 addon。它发现模块、执行可选的 C# 构建规则、生成 GDExtension 类注册代码，再通过 CMake 编译和部署原生库。命令行和生成的 Visual Studio 解决方案共用同一套构建流程。

## 构建 NativeDemo

示例基于 **Godot 4.7.2**，使用 **4.7** 版 C++ API。需要 .NET 10 SDK、CMake 3.21 或更高版本、Python 3，以及当前平台的原生工具链。

| 主机平台 | 原生工具 | 验证情况 |
| --- | --- | --- |
| Windows x64 | MSVC C++ 构建工具、Windows SDK、Visual Studio CMake 生成器 | 已验证 Debug、Release 构建和独立 Release 游戏 |
| Linux x64 / arm64 | Ninja、GCC 或 Clang、SQLite 开发头文件与库 | x64 Debug 游戏和 addon 已在 Godot 中运行 |
| macOS arm64 / x64 | Ninja、Apple Clang、包含 SQLite 的 macOS SDK | 两种架构均已生成 CMake 工程，原生运行待验证 |

1. 将 [godot-cpp 10.0.0-stable 源码](https://github.com/godotengine/godot-cpp/releases/tag/10.0.0-stable)放到 `examples/NativeDemo/.build/godot-cpp/`，也可以在 [project.godot](examples/NativeDemo/project.godot) 中将 `godot_cpp_path` 指向已有源码目录。该目录下应有 `CMakeLists.txt` 和 `gdextension/extension_api-4-7.json`。
2. Windows 用户在 `examples/NativeDemo/` 下自行放置以下同版本的 x64 [SQLite 开发文件](https://sqlite.org/download.html)。如果官方 DLL 包提供的是 `.def` 导出表，可以在 MSVC 开发者终端执行 `lib /machine:x64 /name:sqlite3.dll /def:sqlite3.def /out:sqlite3.lib` 生成导入库。Linux 和 macOS 上的示例链接系统 SQLite。

   ```text
   ThirdParty/SQLite/include/sqlite3.h
   ThirdParty/SQLite/lib/Win64/sqlite3.lib
   ThirdParty/SQLite/bin/Win64/sqlite3.dll
   ```

3. 在仓库根目录编译工具，再进入示例目录构建游戏和 addon。

   ```shell
   dotnet build AZGodotBuildTool/AZGodotBuildTool.csproj -c Debug
   cd examples/NativeDemo
   dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build
   ```

4. 用 Godot 4.7.2 打开 `examples/NativeDemo/project.godot`，按 **F5**。游戏模块查询内存中的 SQLite 数据库，输出 `SQLite score: 42`，addon 在界面上显示 `Hello from LabelStyle!`。

## IDE 和命令行

在 `examples/NativeDemo/` 下执行以下命令。Windows 上第一条命令会生成供 Visual Studio 或 Rider 打开的 `NativeDemo.AZGodotBuildTool.sln`。解决方案中的 Build、Clean、Rebuild 会按当前配置调用工具。Build 每次都能发现新增源码。要让新文件出现在 IDE 文件树中，再执行一次 Generate。

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll generate --ide vs
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build --config release
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll --help
```

用 `generate --ide cmake` 生成 CMake 工程。例如，在 Windows 执行 `generate --ide cmake --platform macos --arch arm64` 可以生成 macOS 工程输入。实际编译在与目标匹配的系统和架构上执行。在 Linux 或 macOS 本机生成工程时，还会生成编译数据库。

## 模块目录

| 相对于 `project.godot` 的路径 | 用途 |
| --- | --- |
| `Source/<模块>/` | 游戏模块，共同链接成一个游戏原生库。 |
| `addons/<addon>/Source/<模块>/` | addon 模块，每个原生 addon 生成自己的库和描述文件。 |
| `<模块目录>/<模块>.Build.cs` | 可选规则，用于声明模块依赖、头文件搜索路径、链接库和运行时文件。 |

工具为头文件中声明的普通 `GDCLASS` 类生成注册代码，在 Scene 初始化阶段先注册基类，再注册派生类。方法、属性和信号在类自己的 `_bind_methods()` 中绑定。

示例中的 [Gameplay](examples/NativeDemo/Source/Gameplay/Gameplay.Build.cs) 依赖 [GameData](examples/NativeDemo/Source/GameData/GameData.Build.cs)，后者配置 SQLite。addon 中的 [DemoLabel](examples/NativeDemo/addons/demo_label/Source/DemoLabel/DemoLabel.Build.cs) 依赖 LabelStyle。依赖方可以使用模块的 `Public/` 头文件。公共依赖会传递给下游，私有依赖用于编译声明它的模块。

## 导出 Windows 示例

先用 `--config release` 构建原生库。[Windows Release 导出预设](examples/NativeDemo/export_presets.cfg)使用的 Godot 4.7.2 标准版 Windows x64 Release 模板路径为 `examples/NativeDemo/.build/export_templates/4.7.2.stable/windows_release_x86_64.exe`。将本地模板放在该位置，或在预设中选择自己的模板。通过 **项目 → 导出 → Windows Release** 导出后，整个 `.build/export/Windows-x64/` 目录可以一起分发，里面包含 EXE、PCK 和运行所需的 DLL。
