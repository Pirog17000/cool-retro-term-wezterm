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

    -WeztermRef main builds on the latest wezterm (what the nightly builds
    use) instead of the pinned commit: the patches are applied onto it.

    Needs: Rust (msvc), Visual Studio 2022 C++ tools, Strawberry Perl (for the
    vendored OpenSSL used by SSH).  Perl is looked up in -PerlDir,
    $env:STRAWBERRY_PERL, C:\Strawberry\perl\bin and PATH.  Machine specific
    settings can go into build.local.ps1 next to this script (not tracked by
    git), e.g.   $PerlDir = 'D:\tools\strawberry\perl\bin'

    Settings saved by the menu in an existing dist folder (crt_state.json,
    wezterm_options.json) survive a rebuild.  build_info.json in the dist
    folder records the version for the Update menu.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm_crt.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build_wezterm_crt.ps1 -WeztermRef main -Zip
#>
param(
    [string]$PerlDir = '',
    [string]$DistDir = 'dist-wezterm',
    # wezterm commit / branch / tag to build on; empty = the pinned commit
    [string]$WeztermRef = '',
    # version recorded in build_info.json (CI passes the release tag)
    [string]$Version = '',
    # re-apply the patches even if the submodule has a development branch
    [switch]$Force,
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$local = Join-Path $root 'build.local.ps1'
if (Test-Path $local) { . $local }

$wez = Join-Path $root 'third_party\wezterm'
$targetDir = Join-Path $root 'build\wezterm-target'

# --- tools -------------------------------------------------------------------
function Find-Perl {
    $candidates = @($PerlDir, $env:STRAWBERRY_PERL, 'C:\Strawberry\perl\bin') | Where-Object { $_ }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'perl.exe')) { return $c }
    }
    # Git for Windows ships a Perl without the modules OpenSSL needs
    $p = Get-Command perl.exe -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -match 'strawberry' } | Select-Object -First 1
    if ($p) { return Split-Path $p.Source }
    throw 'Strawberry Perl not found: pass -PerlDir, set STRAWBERRY_PERL or put $PerlDir into build.local.ps1'
}
$PerlDir = Find-Perl
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$env:PATH = "$PerlDir;$cargoBin;$env:PATH"

# --- sources -----------------------------------------------------------------
$pinned = (git -C $root ls-tree HEAD third_party/wezterm).Split()[2]
if (-not (Test-Path "$wez\Cargo.toml")) {
    Step 'Fetching wezterm submodule'
    git submodule update --init --depth 1 third_party/wezterm
    if ($LASTEXITCODE) { throw 'submodule update failed' }
}

$patches = Get-ChildItem "$root\patches\wezterm\*.patch" | Sort-Object Name
$branch = git -C $wez rev-parse --abbrev-ref HEAD
if ($branch -eq 'crt' -and $WeztermRef -and -not $Force) {
    throw "third_party/wezterm is on the development branch 'crt'; export it first, then pass -Force to rebuild it from patches/"
}

$base = $pinned
if ($WeztermRef) {
    Step "Fetching wezterm $WeztermRef"
    git -C $wez fetch --depth 200 origin $WeztermRef
    if ($LASTEXITCODE) { throw "fetching wezterm $WeztermRef failed" }
    $base = (git -C $wez rev-parse FETCH_HEAD).Trim()
}

if ($branch -ne 'crt' -or $Force) {
    git -C $wez checkout -q --detach $base
    if ($LASTEXITCODE) { throw "checkout of $base failed" }
    Step 'Fetching wezterm dependency submodules'
    git -C $wez submodule update --init --depth 1 --recursive
    if ($LASTEXITCODE) { throw 'wezterm submodules failed' }
    Step "Applying $($patches.Count) patch(es) onto $($base.Substring(0, 10)) as branch crt"
    git -C $wez checkout -q -B crt
    if ($LASTEXITCODE) { throw 'checkout failed' }
    git -C $wez -c user.name=build -c user.email=build@localhost am --3way @($patches.FullName)
    if ($LASTEXITCODE) { git -C $wez am --abort; throw 'applying patches failed' }
} else {
    Step 'Submodule already on branch crt (development mode), not re-applying patches'
    if (-not (Test-Path "$wez\deps\freetype\freetype2\README")) {
        git -C $wez submodule update --init --depth 1 --recursive
        if ($LASTEXITCODE) { throw 'wezterm submodules failed' }
    }
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

# Keep what the settings menu saved in an existing dist folder
$userFiles = 'crt_state.json', 'wezterm_options.json'
$saved = @{}
foreach ($f in $userFiles) {
    $p = Join-Path $dist $f
    if (Test-Path $p) { $saved[$f] = [IO.File]::ReadAllBytes($p) }
}
$oldLua = Join-Path $dist 'wezterm.lua'
$oldLuaBytes = if (Test-Path $oldLua) { [IO.File]::ReadAllBytes($oldLua) } else { $null }

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
Copy-Item "$root\wezterm-crt\update.ps1" $dist

# Retro fonts used by the cool-retro-term profiles
$fontsDst = Join-Path $dist 'fonts'
Get-ChildItem "$root\app\qml\fonts" -Directory | ForEach-Object {
    $d = Join-Path $fontsDst $_.Name
    New-Item -ItemType Directory $d -Force | Out-Null
    Get-ChildItem $_.FullName -File | Where-Object { $_.Extension -in '.ttf', '.otf', '.txt', '' -or $_.Name -like 'LICENSE*' } |
        Copy-Item -Destination $d
}

Copy-Item "$root\app\icons\cool-retro-term.ico" $dist

# Version information for the Update menu
$wezHead = (git -C $wez log -1 --format='%H %cI' $base).Trim().Split(' ')
$crtCommit = (git -C $root rev-parse --short=10 HEAD).Trim()
$luaHash = (Get-FileHash "$dist\wezterm.lua" -Algorithm SHA256).Hash.ToLower()
if (-not $Version) { $Version = 'local-' + (Get-Date -Format 'yyyyMMdd-HHmm') }
$info = [ordered]@{
    version          = $Version
    wezterm_commit   = $wezHead[0]
    wezterm_date     = $wezHead[1]
    crt_commit       = $crtCommit
    built            = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    wezterm_lua_sha256 = $luaHash
}
$info | ConvertTo-Json | Set-Content "$dist\build_info.json" -Encoding ascii

if ($Zip) {
    # the package never contains settings saved by the menu
    $zipPath = Join-Path $root 'cool-retro-term-wezterm-win64.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    Compress-Archive -Path "$dist\*" -DestinationPath $zipPath
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    Set-Content "$zipPath.sha256" "$hash  $(Split-Path $zipPath -Leaf)" -Encoding ascii
    Step "Packed $zipPath"
}

foreach ($f in $saved.Keys) { [IO.File]::WriteAllBytes((Join-Path $dist $f), $saved[$f]) }
if ($oldLuaBytes) {
    $newLuaBytes = [IO.File]::ReadAllBytes("$dist\wezterm.lua")
    if ([Convert]::ToBase64String($oldLuaBytes) -ne [Convert]::ToBase64String($newLuaBytes)) {
        [IO.File]::WriteAllBytes("$dist\wezterm.lua.bak", $oldLuaBytes)
        Step 'The previous wezterm.lua differed: saved as wezterm.lua.bak'
    }
}

Step "Done: $dist\wezterm-gui.exe  ($Version)"
