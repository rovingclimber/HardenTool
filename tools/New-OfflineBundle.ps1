[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet('dsc-v3')]
    [string]$Backend = 'dsc-v3',

    [Parameter()]
    [string]$CompilerVersion = '0.1.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Digest {
    param([Parameter(Mandatory)][string]$Path)
    "sha256:$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant())"
}

function Get-HardenToolGitExecutable {
    $fromPath = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) { return $fromPath.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw 'Git for Windows is required to build an offline bundle. Install it or add git.exe to PATH.'
}

function Get-ActionChangeRank {
    param([Parameter(Mandatory)][string]$ChangeClass)
    @{
        'read-only' = 0
        'reversible' = 1
        'reboot' = 2
        'service-impacting' = 3
        'irreversible' = 4
    }[$ChangeClass]
}

function New-ResolvedAction {
    param(
        [string]$Id,
        [string]$SourceRef,
        [string]$ChangeClass,
        [string]$Rollback,
        [string]$Resource,
        [hashtable]$Properties
    )

    [ordered]@{
        id = $Id
        sourceRef = $SourceRef
        changeClass = $ChangeClass
        rollback = $Rollback
        backend = [ordered]@{
            resource = $Resource
            properties = $Properties
        }
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot 'Test-PolicySchema.ps1'
& $validatorPath -PolicyPath $PolicyPath -Schema device-policy

$gitExecutable = Get-HardenToolGitExecutable
$gitCommit = (& $gitExecutable -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $gitCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'A committed Git checkout is required to build an offline bundle.'
}

$dirtyPaths = & $gitExecutable -C $repositoryRoot status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Unable to determine Git working tree state.' }
if ($dirtyPaths) {
    throw 'Refusing to build from a dirty Git working tree. Commit or stash the policy changes first.'
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Output path already exists: $resolvedOutput. Refusing to overwrite a bundle."
}

$policyFullPath = (Resolve-Path -LiteralPath $PolicyPath).Path
$policy = Get-Content -LiteralPath $policyFullPath -Raw | ConvertFrom-Json
$actions = New-Object System.Collections.Generic.List[object]

foreach ($application in @($policy.spec.applications)) {
    if ($application.state -eq 'absent') {
        $actions.Add((New-ResolvedAction -Id "application.$($application.id).remove" -SourceRef "applications/$($application.id)" -ChangeClass 'irreversible' -Rollback 'manual-runbook' -Resource 'HardenTool.Windows.Package' -Properties @{ id = $application.id; desiredState = 'absent'; removalClass = $application.removalClass }))
    }
    elseif ($application.state -eq 'present') {
        $actions.Add((New-ResolvedAction -Id "application.$($application.id).install" -SourceRef "applications/$($application.id)" -ChangeClass 'reboot' -Rollback 'manual-runbook' -Resource 'HardenTool.Windows.Package' -Properties @{ id = $application.id; desiredState = 'present' }))
    }
}

foreach ($service in @($policy.spec.services)) {
    $actions.Add((New-ResolvedAction -Id "service.$($service.id).$($service.state)" -SourceRef "services/$($service.id)" -ChangeClass 'service-impacting' -Rollback 'manual-runbook' -Resource 'HardenTool.Windows.Service' -Properties @{ name = $service.id; desiredState = $service.state }))
}

foreach ($capability in @($policy.spec.capabilities)) {
    $actions.Add((New-ResolvedAction -Id "capability.$($capability.id).$($capability.state)" -SourceRef "capabilities/$($capability.id)" -ChangeClass 'reversible' -Rollback 'automatic' -Resource 'HardenTool.Windows.Capability' -Properties @{ id = $capability.id; desiredState = $capability.state }))
}

$maximumRank = Get-ActionChangeRank -ChangeClass $policy.spec.changeControl.maximumClass
foreach ($action in $actions) {
    if ((Get-ActionChangeRank -ChangeClass $action.changeClass) -gt $maximumRank) {
        throw "Action '$($action.id)' exceeds policy maximumClass '$($policy.spec.changeControl.maximumClass)'."
    }
}

New-Item -ItemType Directory -Path $resolvedOutput | Out-Null
try {
    $policyTarget = Join-Path $resolvedOutput 'device-policy.json'
    Copy-Item -LiteralPath $policyFullPath -Destination $policyTarget

    $resolvedPolicy = [ordered]@{
        apiVersion = 'hardentool/v1'
        kind = 'ResolvedPolicy'
        source = [ordered]@{
            name = $policy.metadata.name
            version = $policy.metadata.version
            digest = (Get-Sha256Digest -Path $policyFullPath)
            commit = $gitCommit
        }
        release = [ordered]@{
            resolvedAt = (Get-Date).ToUniversalTime().ToString('o')
            compilerVersion = $CompilerVersion
            backend = $Backend
        }
        artifacts = @()
        actions = $actions.ToArray()
    }

    $resolvedTarget = Join-Path $resolvedOutput 'resolved-policy.json'
    $resolvedPolicy | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedTarget -Encoding UTF8
    & $validatorPath -PolicyPath $resolvedTarget -Schema resolved-policy

    $manifest = [ordered]@{
        apiVersion = 'hardentool/v1'
        kind = 'OfflineBundleManifest'
        source = $resolvedPolicy.source
        release = $resolvedPolicy.release
        files = @(
            [ordered]@{ path = 'device-policy.json'; digest = (Get-Sha256Digest -Path $policyTarget) },
            [ordered]@{ path = 'resolved-policy.json'; digest = (Get-Sha256Digest -Path $resolvedTarget) }
        )
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $resolvedOutput 'manifest.json') -Encoding UTF8
}
catch {
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

Write-Host "Created offline bundle: $resolvedOutput"
