param(
    [string]$Version = "0.1.2",
    [string]$Image = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = (Get-Command python -ErrorAction Stop).Source

$ArgsList = @((Join-Path $Root "tools\build_fpk.py"), "--root", $Root, "--version", $Version)
if ($Image) {
    $ArgsList += @("--image", $Image)
}

& $Python @ArgsList
