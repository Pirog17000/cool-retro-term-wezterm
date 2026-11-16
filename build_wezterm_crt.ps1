<#
.SYNOPSIS
    Builds wezterm with the cool-retro-term CRT renderer and assembles a
    portable folder (dist-wezterm\).

.DESCRIPTION
    third_party/wezterm is pinned to an upstream wezterm commit.  Our changes
    live in patches/wezterm/*.patch and are applied onto a local branch "crt"
    inside the submodule (skipped when that branch already exists, e.g. while
    developing).  Use tools/export_wezterm_patches.ps1 to refresh the patches
    after committing on that branch.

    Needs: Rust (msvc), Visual Studio 2022 C++ tools, Strawberry Perl (for the
    vendored OpenSSL used by SSH).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm_crt.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm_crt.ps1 -PerlDir D:\strawberry\perl\bin -Zip
#>
param(
    [string]$PerlDir = $(if ($env:STRAWBERRY_PERL) { $env:STRAWBERRY_PERL } else { 'C:\Strawberry\perl\bin' }),
    [string]$DistDir = 'dist-wezterm',
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$wez = Join-Path $root 'third_party\wezterm'
$targetDir = Join-Path $root 'build\wezterm-target'

if (-not (Test-Path "$PerlDir\perl.exe")) { throw "Strawberry Perl not found in '$PerlDir' (pass -PerlDir)" }
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$env:PATH = "$PerlDir;$cargoBin;$env:PATH"

# --- sources -----------------------------------------------------------------
if (-not (Test-Path "$wez\Cargo.toml")) {
    Step 'Fetching wezterm submodule'
    git submodule update --init --depth 1 third_party/wezterm
    if ($LASTEXITCODE) { throw 'submodule update failed' }
}
if (-not (Test-Path "$wez\deps\freetype\freetype2\README")) {
    Step 'Fetching wezterm dependency submodules'
    git -C $wez submodule update --init --depth 1 --recursive
    if ($LASTEXITCODE) { throw 'wezterm submodules failed' }
}

$branch = git -C $wez rev-parse --abbrev-ref HEAD
if ($branch -ne 'crt') {
    $patches = Get-ChildItem "$root\patches\wezterm\*.patch" | Sort-Object Name
    Step "Applying $($patches.Count) patch(es) onto branch crt"
    git -C $wez checkout -q -B crt
    if ($LASTEXITCODE) { throw 'checkout failed' }
    git -C $wez -c user.name=build -c user.email=build@localhost am --3way @($patches.FullName)
    if ($LASTEXITCODE) { git -C $wez am --abort; throw 'applying patches failed' }
} else {
    Step 'Submodule already on branch crt (development mode), not re-applying patches'
}

# wezterm-gui's build.rs copies runtime DLLs into <wezterm>\target\release
New-Item -ItemType Directory -Force "$wez\target\release" | Out-Null

# --- build -------------------------------------------------------------------
Step 'Building wezterm (release)'
Push-Location $wez
try {
    cargo build --release -p wezterm-gui -p wezterm --target-dir $targetDir
    if ($LASTEXITCODE) { throw 'cargo build failed' }
} finally { Pop-Location }

# --- assemble ----------------------------------------------------------------
Step "Assembling $DistDir"
$dist = Join-Path $root $DistDir
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory $dist | Out-Null

Copy-Item "$targetDir\release\wezterm-gui.exe", "$targetDir\release\wezterm.exe" $dist
$assets = "$wez\assets\windows"
Copy-Item "$assets\conhost\conpty.dll", "$assets\conhost\OpenConsole.exe" $dist
Copy-Item "$assets\angle\libEGL.dll", "$assets\angle\libGLESv2.dll" $dist
New-Item -ItemType Directory "$dist\mesa" | Out-Null
Copy-Item "$assets\mesa\opengl32.dll" "$dist\mesa\"

Copy-Item "$root\wezterm-crt\wezterm.lua" $dist
Copy-Item "$root\wezterm-crt\wezterm_modules" $dist -Recurse

# Retro fonts used by the cool-retro-term profiles
$fontsDst = Join-Path $dist 'fonts'
Get-ChildItem "$root\app\qml\fonts" -Directory | ForEach-Object {
    $d = Join-Path $fontsDst $_.Name
    New-Item -ItemType Directory $d -Force | Out-Null
    Get-ChildItem $_.FullName -File | Where-Object { $_.Extension -in '.ttf', '.otf', '.txt', '' -or $_.Name -like 'LICENSE*' } |
        Copy-Item -Destination $d
}

Copy-Item "$root\app\icons\cool-retro-term.ico" $dist

if ($Zip) {
    $zipPath = Join-Path $root 'wezterm-crt-win64.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    Compress-Archive -Path "$dist\*" -DestinationPath $zipPath
    Step "Packed $zipPath"
}

Step "Done: $dist\wezterm-gui.exe"
