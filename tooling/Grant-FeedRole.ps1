<#
.SYNOPSIS
  Grants the project build service a role on an Azure Artifacts feed, then reads it back.
.DESCRIPTION
  Run this from your own terminal (PowerShell 7). The automation sandbox refuses permission grants, and
  the bootstrap's own PATCH was accepted by the service but applied nothing ({"count":0,"value":[]}).
  The azure-devops CLI's own SDK types identityDescriptor as a string, so the bootstrap's shape was
  valid and the identity reference is the suspect. This script tries the identity references in order
  and reads the permission list back after each one:
    1. graph subject descriptor (svc....), alone and with identityId and displayName
    2. IMS descriptor ("Microsoft.TeamFoundation.ServiceIdentity;..."), with and without identityId
    3. identityId only
    4. identityDescriptor as the {identityType, identifier} object from the 7.1 reference page
  Auth: $env:AZDO_PAT (or -Pat) against the documented feeds.dev.azure.com endpoint. Without a PAT it
  goes through `az devops invoke` with the credential the azure-devops extension holds.
.EXAMPLE
  pwsh ./tooling/Grant-FeedRole.ps1
.EXAMPLE
  pwsh ./tooling/Grant-FeedRole.ps1 -Role collaborator -Identity 'Project Collection Build Service (coolhome)'
#>
[CmdletBinding()]
param(
    [string]$Org = 'https://dev.azure.com/coolhome',
    [string]$Project = 'Meridian',
    [string]$Feed = 'meridian',
    [ValidateSet('reader', 'collaborator', 'contributor', 'administrator')][string]$Role = 'contributor',
    [string]$Identity = 'Meridian Build Service (coolhome)',
    [string]$Pat = $env:AZDO_PAT,
    [switch]$ReadOnly   # resolve the identity and report the current role, change nothing
)
$ErrorActionPreference = 'Stop'
$orgName = ($Org -replace '^https://dev\.azure\.com/', '').Trim('/')
$feedsBase = "https://feeds.dev.azure.com/$orgName/$([uri]::EscapeDataString($Project))/_apis/packaging/Feeds/$Feed/permissions"
$headers = if ($Pat) { @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat")) } } else { $null }
"auth: $(if ($headers) { 'PAT' } else { 'az devops credential' })"

function Invoke-Cli {
    param([string]$Method, [string]$Area, [string]$Resource, [string[]]$Route, [string[]]$Query, [string]$BodyJson)
    $cli = @('devops', 'invoke', '--org', $Org, '--area', $Area, '--resource', $Resource, '--http-method', $Method, '--api-version', '7.1-preview', '-o', 'json', '--only-show-errors')
    if ($Route) { $cli += '--route-parameters'; $cli += $Route }
    if ($Query) { $cli += '--query-parameters'; $cli += $Query }
    $file = $null
    try {
        if ($BodyJson) {
            $file = Join-Path ([IO.Path]::GetTempPath()) "feedrole-$([guid]::NewGuid().ToString('n')).json"
            [IO.File]::WriteAllText($file, $BodyJson, [Text.UTF8Encoding]::new($false))
            $cli += @('--in-file', $file, '--encoding', 'utf-8')
        }
        $out = & az @cli 2>&1
        if ($LASTEXITCODE -ne 0) { throw "az devops invoke failed: $out" }
        $text = ($out | Where-Object { $_ -is [string] }) -join "`n"
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json -Depth 32
    }
    finally { if ($file -and (Test-Path $file)) { Remove-Item $file -Force } }
}

function Get-Permissions {
    if ($headers) { return @((Invoke-RestMethod -Method GET -Uri "${feedsBase}?includeIds=true&api-version=7.1-preview.1" -Headers $headers).value) }
    return @((Invoke-Cli -Method GET -Area packaging -Resource permissions -Route @("project=$Project", "feedId=$Feed") -Query @('includeIds=true')).value)
}

function Set-Permissions([string]$BodyJson) {
    if ($headers) { return Invoke-RestMethod -Method PATCH -Uri "${feedsBase}?api-version=7.1-preview.1" -Headers $headers -ContentType 'application/json' -Body $BodyJson }
    return Invoke-Cli -Method PATCH -Area packaging -Resource permissions -Route @("project=$Project", "feedId=$Feed") -BodyJson $BodyJson
}

# 1. Resolve the identity. The project build service descriptor ends with :Build:<projectId>.
$projectId = (az devops project show --org $Org --project $Project -o json | ConvertFrom-Json).id
$found = @((Invoke-Cli -Method GET -Area IMS -Resource Identities -Query @('searchFilter=General', "filterValue=$Identity", 'queryMembership=None')).value)
$id = $found | Where-Object { $_.descriptor -like "*:Build:$projectId" } | Select-Object -First 1
if (-not $id) { $id = $found | Select-Object -First 1 }
if (-not $id) { throw "identity '$Identity' not found in $Org" }
"identity: $Identity  id=$($id.id)  descriptor=$($id.descriptor)"

# The graph subject descriptor (svc.../vssgp...) is what the Terraform provider and the portal hand to this
# API; the feeds service resolves it through Graph. The IMS descriptor the bootstrap sent is what the API
# *returns*, and the service dropped it silently, so the graph form goes first.
$graph = $null
try { $graph = (Invoke-Cli -Method GET -Area graph -Resource descriptors -Route @("storageKey=$($id.id)")).value }
catch { "graph descriptor lookup failed, skipping those attempts: $($_.Exception.Message)" }
if ($graph) { "graph descriptor: $graph" }

# 2. Already granted?
$isTarget = { $_.identityDescriptor -eq $id.descriptor -or ($_.PSObject.Properties['identityId'] -and $_.identityId -eq $id.id) }
$current = Get-Permissions | Where-Object $isTarget | Select-Object -First 1
if ($current -and $current.role -in @($Role, 'administrator')) { "already $($current.role) on feed '$Feed'; nothing to do"; exit 0 }
"current role: $(if ($current) { $current.role } else { 'none (no entry)' })"
if ($ReadOnly) { "read-only: stopping before any change"; exit 0 }

# 3. Try each request shape until the read-back shows the role. The azure-devops CLI's own SDK types
#    identityDescriptor as a string, so the object form from the 7.1 reference page goes last.
$type, $identifier = $id.descriptor -split ';', 2
$attempts = @()
if ($graph) {
    $attempts += @{ name = 'graph descriptor only';                       body = @(@{ identityDescriptor = $graph; role = $Role }) }
    $attempts += @{ name = 'graph descriptor + identityId + displayName'; body = @(@{ identityDescriptor = $graph; identityId = $id.id; displayName = $Identity; role = $Role }) }
}
$attempts += @{ name = 'IMS descriptor + identityId + displayName (bootstrap shape)'; body = @(@{ identityDescriptor = $id.descriptor; identityId = $id.id; displayName = $Identity; role = $Role }) }
$attempts += @{ name = 'IMS descriptor only';                                        body = @(@{ identityDescriptor = $id.descriptor; role = $Role }) }
$attempts += @{ name = 'identityId only';                                            body = @(@{ identityId = $id.id; displayName = $Identity; role = $Role }) }
$attempts += @{ name = 'object descriptor (7.1 reference shape)';                    body = @(@{ identityDescriptor = @{ identityType = $type; identifier = $identifier }; identityId = $id.id; displayName = $Identity; role = $Role }) }
foreach ($a in $attempts) {
    $json = ConvertTo-Json -InputObject $a.body -Depth 6 -Compress -AsArray
    "PATCH ($($a.name)): $json"
    try {
        $resp = Set-Permissions $json
        $respText = if ($null -ne $resp) { $resp | ConvertTo-Json -Depth 6 -Compress } else { '(empty)' }
        "  response: $respText"
    }
    catch { "  request failed: $($_.Exception.Message)"; continue }
    $after = Get-Permissions | Where-Object $isTarget | Select-Object -First 1
    if ($after -and $after.role -in @($Role, 'administrator')) { "ok: '$Identity' is now $($after.role) on feed '$Feed'"; exit 0 }
    "  not persisted (read-back: $(if ($after) { $after.role } else { 'no entry' }))"
}
Write-Warning "No request shape persisted. Portal fallback: Artifacts > $Feed > gear > Permissions > Add users/groups > '$Identity' > Feed Publisher (Contributor). Paste this output back so the bootstrap can be fixed to match whatever works."
exit 1
