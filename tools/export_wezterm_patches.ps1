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

# The repository is meant to be public: no personal name or e-mail in the
# patch headers, whatever identity the commits on "crt" were made with.
$author = 'From: cool-retro-term-wezterm <build@localhost>'
foreach ($f in Get-ChildItem "$out\*.patch") {
    # Latin-1 maps every byte to one char, so the rest of the file stays byte-exact
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString([IO.File]::ReadAllBytes($f.FullName))
    $text = ([regex]'(?m)^From: [^\r\n]*').Replace($text, $author, 1)
    [IO.File]::WriteAllBytes($f.FullName, $latin1.GetBytes($text))
}
Write-Host "Exported patches against $pinned to $out"
