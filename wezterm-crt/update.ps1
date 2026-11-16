<#
.SYNOPSIS
    Installs a cool-retro-term-wezterm release into this portable folder.

.DESCRIPTION
    Started by Settings > Update in wezterm.  Downloads the release package
    (with the GitHub CLI when it is installed, which also works for private
    repositories, otherwise from the public GitHub API), checks its SHA-256,
    asks wezterm to close, replaces the program files and starts wezterm
    again.

    Kept as they are: crt_state.json and wezterm_options.json (settings saved
    by the menu) and an edited wezterm.lua; the new wezterm.lua is then saved
    next to it as wezterm.lua.new.  The previous version is copied to
    %TEMP%\crt-update\<tag>\backup first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File update.ps1 -Dir . -Repo owner/repo -Tag crt-20261116-1200
#>
param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [string]$Repo = '',
    [string]$Tag = '',
    # install a local package instead of downloading one
    [string]$ZipPath = '',
    [switch]$NoRestart,
    # already running in its own console window
    [switch]$Spawned,
    # no "press Enter" at the end (tests)
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# wezterm starts this script without a window; reopen it in a console window
# of its own, which shows the progress and outlives wezterm.
if (-not $Spawned) {
    function Q($s) { '"' + ($s -replace '"', '') + '"' }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q $PSCommandPath), '-Dir', (Q $Dir), '-Spawned')
    if ($Repo) { $a += '-Repo', (Q $Repo) }
    if ($Tag) { $a += '-Tag', (Q $Tag) }
    if ($ZipPath) { $a += '-ZipPath', (Q $ZipPath) }
    if ($NoRestart) { $a += '-NoRestart' }
    Start-Process powershell.exe -ArgumentList ($a -join ' ')
    exit 0
}

$name = if ($Tag) { $Tag } else { 'local' }
try { $Host.UI.RawUI.WindowTitle = "cool-retro-term-wezterm update $name" } catch {}
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Done($code) {
    if (-not $Quiet) { Read-Host 'Press Enter to close this window' | Out-Null }
    exit $code
}

try {
    $Dir = (Resolve-Path $Dir).Path.TrimEnd('\')
    if (-not (Test-Path (Join-Path $Dir 'wezterm-gui.exe'))) { throw "$Dir is not a cool-retro-term-wezterm folder" }
    $work = Join-Path $env:TEMP "crt-update\$name"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory $work | Out-Null

    # --- download ---------------------------------------------------------------
    if (-not $ZipPath) {
        if (-not $Repo -or -not $Tag) { throw '-Repo and -Tag are needed to download a release' }
        Say "Downloading $Tag from $Repo"
        $downloaded = $false
        $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
        if ($gh) {
            & $gh.Source release download $Tag --repo $Repo --pattern '*.zip' --pattern '*.sha256' --dir $work
            $downloaded = ($LASTEXITCODE -eq 0)
        }
        if (-not $downloaded) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $headers = @{ 'User-Agent' = 'cool-retro-term-wezterm-update'; 'Accept' = 'application/vnd.github+json' }
            $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers
            foreach ($asset in $rel.assets) {
                if ($asset.name -like '*.zip' -or $asset.name -like '*.sha256') {
                    Invoke-WebRequest $asset.browser_download_url -OutFile (Join-Path $work $asset.name) -UseBasicParsing -Headers @{ 'User-Agent' = $headers['User-Agent'] }
                }
            }
        }
        $zip = Get-ChildItem $work -Filter *.zip | Select-Object -First 1
        if (-not $zip) { throw 'the release has no .zip package' }
        $ZipPath = $zip.FullName
        $sum = Get-ChildItem $work -Filter *.sha256 | Select-Object -First 1
        if (-not $sum) { throw 'the release has no .sha256 checksum' }
        $expected = ((Get-Content $sum.FullName -Raw).Trim() -split '\s+')[0].ToLower()
        $actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
        if ($expected -ne $actual) { throw "checksum mismatch: got $actual, the release says $expected" }
        Say 'Checksum OK'
    }

    # --- unpack -----------------------------------------------------------------
    $stage = Join-Path $work 'package'
    Expand-Archive $ZipPath $stage
    if (-not (Test-Path (Join-Path $stage 'wezterm-gui.exe'))) { throw 'the package does not contain wezterm-gui.exe' }

    # --- close wezterm ----------------------------------------------------------
    function Get-Running {
        @(Get-Process wezterm-gui, wezterm -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.StartsWith($Dir + '\', [StringComparison]::OrdinalIgnoreCase) })
    }
    $running = Get-Running
    if ($running.Count) {
        Say 'Closing wezterm (confirm in wezterm if it asks)'
        foreach ($p in $running) { [void]$p.CloseMainWindow() }
        $ticks = 0
        while ((Get-Running).Count) {
            Start-Sleep -Milliseconds 500
            $ticks++
            if ($ticks % 20 -eq 0) { Write-Host '    waiting for all wezterm windows to close ...' }
        }
    }

    # --- install ----------------------------------------------------------------
    $keep = @('crt_state.json', 'wezterm_options.json')

    # An edited wezterm.lua stays; the shipped one goes next to it.
    $luaNote = $null
    $curLua = Join-Path $Dir 'wezterm.lua'
    $newLua = Join-Path $stage 'wezterm.lua'
    if ((Test-Path $curLua) -and (Test-Path $newLua)) {
        $curHash = (Get-FileHash $curLua -Algorithm SHA256).Hash.ToLower()
        $newHash = (Get-FileHash $newLua -Algorithm SHA256).Hash.ToLower()
        $shipped = $null
        $infoPath = Join-Path $Dir 'build_info.json'
        if (Test-Path $infoPath) {
            try { $shipped = (Get-Content $infoPath -Raw | ConvertFrom-Json).wezterm_lua_sha256 } catch {}
        }
        if ($curHash -ne $newHash -and $curHash -ne $shipped) {
            $keep += 'wezterm.lua'
            Copy-Item $newLua (Join-Path $Dir 'wezterm.lua.new') -Force
            $luaNote = 'Your wezterm.lua was edited, so it was kept; the new default is in wezterm.lua.new.'
        }
    }

    Say "Saving the current version to $work\backup"
    robocopy $Dir (Join-Path $work 'backup') /E /XF $keep /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "backup failed (robocopy $LASTEXITCODE)" }

    Say "Installing into $Dir"
    robocopy $stage $Dir /E /XF $keep /R:20 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying the new files failed (robocopy $LASTEXITCODE); the previous version is in $work\backup" }

    $info = Join-Path $Dir 'build_info.json'
    $ver = if (Test-Path $info) { (Get-Content $info -Raw | ConvertFrom-Json).version } else { $name }
    Say "Installed $ver"
    if ($luaNote) { Write-Host $luaNote -ForegroundColor Yellow }

    if (-not $NoRestart) {
        Start-Process (Join-Path $Dir 'wezterm-gui.exe') -WorkingDirectory $env:USERPROFILE
    }
    if ($luaNote) { Done 0 }
    if (-not $Quiet) { Start-Sleep 3 }
    exit 0
} catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    Done 1
}
