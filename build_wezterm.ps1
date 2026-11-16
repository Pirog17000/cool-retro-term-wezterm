<#
.SYNOPSIS
    Builds cool-retro-term with the wezterm-term emulation core and assembles
    a portable folder (dist\) with the exe, Qt runtime, QML plugin, wezbridge
    and wezterm's ConPTY host.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm.ps1 -QtDir D:\Qt\6.8.3\msvc2022_64 -Zip
#>
param(
    [string]$QtDir = $(if ($env:QTDIR) { $env:QTDIR } else { 'C:\Qt\6.8.3\msvc2022_64' }),
    [string]$BuildDir = 'build',
    [string]$DistDir = 'dist',
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not (Test-Path "$QtDir\bin\windeployqt.exe")) {
    throw "Qt not found at '$QtDir' (pass -QtDir or set QTDIR)"
}
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if (Test-Path $cargoBin) { $env:PATH = "$cargoBin;$env:PATH" }

if (-not (Test-Path 'third_party\wezterm\term\Cargo.toml')) {
    Step 'Fetching wezterm submodule'
    git submodule update --init --depth 1 third_party/wezterm
    if ($LASTEXITCODE) { throw 'submodule update failed' }
}
if (-not (Test-Path 'KDSingleApplication\src\kdsingleapplication.cpp')) {
    git submodule update --init KDSingleApplication
}

Step 'Configuring (CMake, Visual Studio 2022)'
cmake -S . -B $BuildDir -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_PREFIX_PATH=$QtDir"
if ($LASTEXITCODE) { throw 'cmake configure failed' }

Step 'Building (Release)'
cmake --build $BuildDir --config Release --parallel
if ($LASTEXITCODE) { throw 'build failed' }

Step "Assembling $DistDir"
$dist = Join-Path $root $DistDir
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory $dist | Out-Null

$exeDir = Join-Path $BuildDir 'app\Release'
Copy-Item "$exeDir\cool-retro-term.exe", "$exeDir\wezbridge.dll", "$exeDir\conpty.dll", "$exeDir\OpenConsole.exe" $dist
# Other shared libs built by CMake (KDSingleApplication)
Get-ChildItem "$BuildDir\bin\Release\*.dll" -ErrorAction SilentlyContinue | Copy-Item -Destination $dist

# QML plugin
$pluginDst = Join-Path $dist 'qml\QMLTermWidget'
New-Item -ItemType Directory $pluginDst -Force | Out-Null
Copy-Item "$BuildDir\QMLTermWidget\*" $pluginDst -Recurse -Force
Copy-Item "$BuildDir\qmltermwidget\Release\qmltermwidget.dll" $pluginDst -Force

# Qt runtime
& "$QtDir\bin\windeployqt.exe" --release --qmldir "$root\app\qml" --dir $dist "$dist\cool-retro-term.exe"
if ($LASTEXITCODE) { throw 'windeployqt failed' }
& "$QtDir\bin\windeployqt.exe" --release --no-translations --dir $dist "$pluginDst\qmltermwidget.dll"
if ($LASTEXITCODE) { throw 'windeployqt (plugin) failed' }

if ($Zip) {
    $zipPath = Join-Path $root 'cool-retro-term-wezterm-win64.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    Compress-Archive -Path "$dist\*" -DestinationPath $zipPath
    Step "Packed $zipPath"
}

Step "Done: $dist\cool-retro-term.exe"
