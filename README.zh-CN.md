# AZGodotProjectManager

[English](README.md)

AZGodotProjectManager 是一个 Godot 桌面项目管理器，用于创建、导入、扫描和打开项目。你可以单独为某个项目启用 C++，由管理器调用 AZGodotBuildTool 生成 IDE 工程，一次构建游戏本体和原生 addon。

## 打开第一个项目

1. **启动管理器**。使用 Windows 打包版时，直接运行 `AZGodotProjectManager.exe`。从源码运行时，在 Godot 4.7.2 中导入[管理器的 Godot 工程](AZGodotProjectManager/project.godot)，打开后按 **F5**。
2. **选择编辑器**。点击 **环境设置**，在 **Godot 编辑器** 一栏选择本机的编辑器可执行文件。管理器支持 Godot 4.3 至 4.7 的稳定版编辑器，含各次版本的补丁版本，选中其他版本时会弹窗提示。将鼠标停在字段标题最右侧的 **?** 上，可查看该项支持的版本。
3. **添加项目**。点击 **创建** 新建项目，点击 **导入** 选择已有项目的目录或 `project.godot` 文件，或点击 **扫描** 查找某个目录下的项目。导入或扫描后，如果弹窗询问是否启用 C++，可以选择 **保留当前项目**，沿用原有配置。
4. **打开项目**。双击项目行，或选中后点击 **打开项目**，即可进入该项目的编辑器。要打开所选引擎自带的项目管理器，点击 **打开原版 Godot**。

右上角的语言按钮显示当前语言，点击可切换简体中文和英语。管理器会记住你的选择。

## 为项目启用 C++

C++ 构建需要 .NET 10 SDK、CMake 3.21 或更高版本、Python 3，以及目标平台的原生工具链。

| 目标平台 | 原生工具 | NativeDemo 验证情况 |
| --- | --- | --- |
| Windows x64 | MSVC C++ 构建工具、Windows SDK、Visual Studio CMake 生成器 | 已验证 Debug 和 Release 构建，以及导出的 Release 游戏 |
| Linux x64 / arm64 | Ninja 和 GCC 或 Clang | 已在 x64 Debug 下用 Godot 运行游戏和 addon |
| macOS arm64 / x64 | Ninja、Apple Clang、macOS SDK | 已为两种架构生成 CMake 工程，本机构建和运行待验证 |

1. 从源码运行管理器时，先在仓库根目录执行下面的命令，编译一次 C# 构建工具。Windows 打包版已在 `BuildTool/` 中包含该工具。

   ```shell
   dotnet build AZGodotBuildTool/AZGodotBuildTool.csproj -c Debug
   ```

2. 打开 **环境设置**，将 **godot-cpp 源码目录** 指向兼容版本的源码根目录。当前支持的 godot-cpp `10.0.0-stable` 包含 Godot 4.3 至 4.7 的 API。管理器和命令行都从项目的 `[application] config/features` 读取主、次版本。例如，4.3 项目需要 `CMakeLists.txt` 和 `gdextension/extension_api-4-3.json`。项目版本变更后，需要重新构建要分发的各个平台和配置。如果所选目录中没有可用的 SDK，可以重新选择目录，也可以选择版本和安装位置，点击 **确认下载**。
3. 新建项目时，勾选 **使用 C++（AZGodotBuildTool）**。对于已有项目，勾选该项目行右上角的 **启用 C++**。如果检测到已有 C++ 源码，按钮文字为 **接入 C++ 构建**。行内复选框只作用于这一行的项目。扫描出多个项目时，也可以在转换弹窗中逐个勾选。
4. 管理器将构建工具和 godot-cpp 的路径写入该项目的 `project.godot`，按需创建起始模块，生成 IDE 工程并执行首次 Debug 构建。已有项目会保留原来的主场景。点击 **构建输出** 可查看编译日志。构建失败时，修复日志指出的问题后即可在同一行重试。

## 仓库结构

| 目录 | 从哪里开始 |
| --- | --- |
| `AZGodotProjectManager/` | 在 Godot 中打开 [project.godot](AZGodotProjectManager/project.godot) 开发桌面界面。项目列表、语言切换和构建按钮的逻辑在 [main.gd](AZGodotProjectManager/main.gd)。 |
| `AZGodotBuildTool/` | 在 Rider 或 Visual Studio 中打开 [AZGodotBuildTool.csproj](AZGodotBuildTool/AZGodotBuildTool.csproj) 开发 C# 命令行工具。工程生成、编译和部署从 [Program.cs](AZGodotBuildTool/Program.cs) 进入。 |
| `examples/NativeDemo/` | 编译原生库后，用 Godot 打开[示例工程](examples/NativeDemo/project.godot)。[Main.tscn](examples/NativeDemo/Main.tscn) 以内置 `Control` 为根节点，下面各挂一个游戏节点和一个 addon 标签节点。 |

## 构建并运行 NativeDemo

**准备依赖**。先用上面的 `dotnet build` 命令编译构建工具。示例默认在 `examples/NativeDemo/.build/godot-cpp/` 查找 godot-cpp。要复用已有源码，可在示例的 `project.godot` 中将 `[AZGodotBuildTool]` 下的 `godot_cpp_path` 改为对应目录。

SQLite 是示例中 `GameData` 模块的依赖。Windows 下需自行准备配套的 SQLite 头文件、x64 导入库和 DLL，放到 `examples/NativeDemo/` 下的以下位置。若 DLL 包提供的是导出定义文件，可在 MSVC 开发者终端执行 `lib /machine:x64 /name:sqlite3.dll /def:sqlite3.def /out:sqlite3.lib` 生成导入库。

```text
ThirdParty/SQLite/include/sqlite3.h
ThirdParty/SQLite/lib/Win64/sqlite3.lib
ThirdParty/SQLite/bin/Win64/sqlite3.dll
```

Linux 下需要安装 SQLite 开发头文件和库。macOS 下使用系统 SDK 提供的 SQLite。

**编译游戏和 addon**。从仓库根目录执行下面的命令。

```shell
cd examples/NativeDemo
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build
```

用 Godot 打开示例并按 **F5**。游戏节点查询内存中的 SQLite 数据库，在「输出」面板打印 `SQLite score: 42`。addon 会在游戏窗口显示 `Hello from LabelStyle!`。

### IDE 与命令行

在 Windows 上，从 `examples/NativeDemo/` 执行下面的命令，为 Rider 或 Visual Studio 生成解决方案。

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll generate --ide vs
```

打开 `NativeDemo.AZGodotBuildTool.sln`。在 IDE 中执行 Build、Clean 或 Rebuild 时，解决方案会按当前配置调用同一个项目级构建工具。每次构建都会发现新增的源码文件。要让它们显示在 IDE 文件树中，再执行一次 `generate`。

使用 `generate --ide cmake` 可以生成 CMake 工程，也可为其他平台生成工程文件。例如，在 Windows 上执行 `generate --ide cmake --platform macos --arch arm64` 可生成 macOS arm64 的工程。实际编译需要在与目标系统和架构匹配的主机上进行。Linux 和 macOS 本机生成工程时，还会生成 `compile_commands.json`。

### 模块与 addon

构建工具从 `Source/<Module>/` 发现游戏模块，将它们链接为一个游戏库。在 `addons/<addon>/Source/<Module>/` 下，每个 addon 的模块会链接为该 addon 自己的库。可选的 `<Module>.Build.cs` 用于声明模块依赖、头文件目录、链接库和运行时文件。

- 游戏的 `Gameplay` 私有依赖 `GameData`，用它提供的接口读取存档数据。SQLite 的配置集中在 `GameData` 中。[Gameplay 构建规则](examples/NativeDemo/Source/Gameplay/Gameplay.Build.cs) · [GameData 构建规则](examples/NativeDemo/Source/GameData/GameData.Build.cs)
- addon 的 `DemoLabel` 依赖 `LabelStyle` 来获取显示文字。依赖方可以使用模块 `Public/` 中的头文件。公共依赖会传递给下游模块，私有依赖仅用于编译声明它的模块。[DemoLabel 构建规则](examples/NativeDemo/addons/demo_label/Source/DemoLabel/DemoLabel.Build.cs)

构建工具为模块头文件中声明的普通 `GDCLASS` 类型生成注册代码，在 Godot 的场景初始化阶段先注册基类，再注册派生类。方法、属性和信号在类自己的 `_bind_methods()` 中绑定。构建完成后，工具部署原生库，并将当前平台的库映射写入对应的 `.gdextension` 文件。

## 将项目管理器打包为 Windows 应用

在仓库根目录运行打包脚本，将编辑器路径换成本机的 Godot 4.7.2 可执行文件。

```powershell
.\AZGodotProjectManager\package_windows.ps1 -Editor 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
```

脚本会发布 C# 构建工具，并使用已安装的 Windows Release 模板导出管理器。要指定本地模板，可追加 `-ReleaseTemplate 'C:\path\to\windows_release_x86_64.exe'`。分发时复制整个 `AZGodotProjectManager/.build/Windows-x64/` 目录，让可执行文件、PCK 和 `BuildTool/` 保持在一起。[管理器打包脚本](AZGodotProjectManager/package_windows.ps1)

## 将 NativeDemo 游戏导出为 Windows 应用

在 `examples/NativeDemo/` 下执行下面的命令，编译游戏和 addon 的 Release 原生库。

```shell
dotnet ../../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll build --config release
```

在 Godot 中打开示例，选择 **项目 → 导出 → Windows Release**。预设使用 Godot 4.7.2 标准版 Windows x64 Release 模板，路径为示例目录下的 `.build/export_templates/4.7.2.stable/windows_release_x86_64.exe`。将本地模板放到该位置，或在预设中选择它的实际路径。导出后分发整个 `.build/export/Windows-x64/` 目录，其中包含 `NativeDemo.exe`、PCK 和 DLL。[示例游戏导出预设](examples/NativeDemo/export_presets.cfg)
