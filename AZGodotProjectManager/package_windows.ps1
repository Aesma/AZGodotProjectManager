param(
    [Parameter(Mandatory)][string]$Editor,
    [string]$ReleaseTemplate
)
$ErrorActionPreference = 'Stop'
$app = $PSScriptRoot
$out = [IO.Directory]::CreateDirectory((Join-Path $app '.build/Windows-x64')).FullName
$editorExe = (Resolve-Path -LiteralPath $Editor).Path
$project = Join-Path (Split-Path -Parent $app) 'AZGodotBuildTool/AZGodotBuildTool.csproj'
& dotnet publish $project -c Release --no-self-contained -p:UseAppHost=false -p:NuGetAudit=false -o (Join-Path $out 'BuildTool')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Godot reads the preset from the project. Use a private export project when a
# local template is supplied so a user's export settings are never rewritten.
$source = $app
if ($ReleaseTemplate) {
    $template = (Resolve-Path -LiteralPath $ReleaseTemplate).Path.Replace('\', '/')
    $source = [IO.Directory]::CreateDirectory((Join-Path $app '.build/export-project')).FullName
    foreach ($name in 'scripts','ui','templates') {
        $dest = [IO.Directory]::CreateDirectory((Join-Path $source $name)).FullName
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $app $name) -File) {
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
        }
    }
    foreach ($name in 'project.godot','Main.tscn','main.gd') {
        Copy-Item -LiteralPath (Join-Path $app $name) -Destination $source -Force
    }
    $preset = [IO.File]::ReadAllText((Join-Path $app 'export_presets.cfg'))
    $preset = $preset.Replace('custom_template/release=""', ('custom_template/release="' + $template + '"'))
    [IO.File]::WriteAllText((Join-Path $source 'export_presets.cfg'), $preset)
}
& $editorExe --headless --path $source --export-release 'Windows Release' (Join-Path $out 'AZGodotProjectManager.exe')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output $out
