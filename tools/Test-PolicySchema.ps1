[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PolicyPath,
    [Parameter()]
    [ValidateSet('device-policy', 'resolved-policy')]
    [string]$Schema = 'device-policy'
)

if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Policy file not found: $PolicyPath"
}

$raw = Get-Content -LiteralPath $PolicyPath -Raw
try {
    $policy = $raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Policy is not valid JSON: $($_.Exception.Message)"
}

if ($policy.apiVersion -ne 'hardentool/v1') { throw 'apiVersion must be hardentool/v1.' }

if ($Schema -eq 'device-policy') {
    if ($policy.kind -ne 'DevicePolicy') { throw 'kind must be DevicePolicy.' }
    if ([string]::IsNullOrWhiteSpace($policy.metadata.name)) { throw 'metadata.name is required.' }
    if ([string]::IsNullOrWhiteSpace($policy.metadata.version)) { throw 'metadata.version is required.' }
    if ($policy.spec.preservation.unknownApplications -ne 'preserve') { throw 'unknown applications must be preserved.' }
    if ($policy.spec.preservation.supplierApplications -ne 'preserve') { throw 'supplier applications must be preserved.' }
    if ($policy.spec.preservation.driverStore -ne 'preserve') { throw 'driver store must be preserved.' }
    if ($policy.spec.changeControl.unattended -ne $false) { throw 'unattended remediation is not permitted in v1.' }

    foreach ($application in @($policy.spec.applications)) {
        if ($application.state -eq 'absent' -and $application.removalClass -ne 'approved-removable') {
            throw "Application '$($application.id)' is absent without approved-removable classification."
        }
    }
}
else {
    if ($policy.kind -ne 'ResolvedPolicy') { throw 'kind must be ResolvedPolicy.' }
    foreach ($artifact in @($policy.artifacts)) {
        if ($artifact.digest -notmatch '^sha256:[a-f0-9]{64}$') { throw "Artifact '$($artifact.id)' has an invalid SHA-256 digest." }
    }
}

Write-Host "Valid policy: $PolicyPath"
