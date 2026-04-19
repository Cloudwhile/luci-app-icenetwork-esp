param(
    [Parameter(Mandatory = $true)]
    [string]$OpenWrtRoot
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetPath = Join-Path $OpenWrtRoot "package\luci-app-icenetwork-esp"

if (-not (Test-Path $OpenWrtRoot)) {
    throw "OpenWrt root does not exist: $OpenWrtRoot"
}

if (Test-Path $targetPath) {
    Remove-Item $targetPath -Recurse -Force
}

New-Item -ItemType Junction -Path $targetPath -Target $repoRoot | Out-Null
Write-Host "Linked package to: $targetPath"
