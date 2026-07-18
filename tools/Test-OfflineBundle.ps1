[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BundlePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$manifestPath = Join-Path $bundle 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'manifest.json is missing.' }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.apiVersion -ne 'hardentool/v1' -or $manifest.kind -ne 'OfflineBundleManifest') {
    throw 'Manifest is not a HardenTool v1 offline bundle manifest.'
}

foreach ($file in @($manifest.files)) {
    $path = Join-Path $bundle $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bundle member is missing: $($file.path)" }
    $actual = "sha256:$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())"
    if ($actual -ne $file.digest) { throw "Digest mismatch for $($file.path)." }
}

& (Join-Path $PSScriptRoot 'Test-PolicySchema.ps1') -PolicyPath (Join-Path $bundle 'device-policy.json') -Schema device-policy
& (Join-Path $PSScriptRoot 'Test-PolicySchema.ps1') -PolicyPath (Join-Path $bundle 'resolved-policy.json') -Schema resolved-policy
Write-Host "Valid offline bundle: $bundle"
