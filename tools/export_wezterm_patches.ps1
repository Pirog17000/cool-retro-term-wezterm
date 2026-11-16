<#
.SYNOPSIS
    Exports the commits on third_party/wezterm's local "crt" branch (on top of
    the pinned upstream commit) into patches/wezterm/*.patch.

.DESCRIPTION
    Workflow: edit code inside third_party/wezterm on branch "crt", commit
    there, run this script, then commit patches/ in the main repository.
    The submodule pointer itself always stays on the upstream commit.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$wez = Join-Path $root 'third_party\wezterm'

# Upstream commit recorded in the main repository for the submodule
$pinned = (git -C $root ls-tree HEAD third_party/wezterm).Split()[2]
if (-not $pinned) { throw 'cannot determine pinned wezterm commit' }

$out = Join-Path $root 'patches\wezterm'
if (Test-Path $out) { Remove-Item "$out\*.patch" -Force }
New-Item -ItemType Directory $out -Force | Out-Null

git -C $wez format-patch --binary --no-signature --zero-commit -o $out "$pinned..crt"
if ($LASTEXITCODE) { throw 'format-patch failed' }
Write-Host "Exported patches against $pinned to $out"
