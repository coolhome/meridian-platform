<#
.SYNOPSIS
  Grants the project build service a role on an Azure Artifacts feed, then reads it back.
.DESCRIPTION
  Initialize-AzureDevOps.ps1 makes this grant itself; this script exists to make or inspect it on its own.
  History, because it shaped two handoffs: for two sessions every PATCH to packaging/feeds/{feed}/permissions
  returned HTTP 200 with {"count":0,"value":[]} and persisted nothing, and the conclusion was that the
  route refuses build-service identities. The real cause was one token in this file and the bootstrap:
  `ConvertTo-Json -InputObject @(...) -AsArray` wraps an array that is already an array, so the wire
  body was [[{...}]] -- an array containing an array, not a FeedPermission[] -- and the service accepted
  it as "zero permissions to set". With the body fixed, the very first shape (IMS descriptor +
  identityId + displayName) persisted on the first try (2026-09-21). The other shapes stay as a
  diagnostic ladder for the next organization; the identity form was never the problem.
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
    param([string]$Method, [string]$Area, [string]$Resource, [string[]]$Route, [string[]]$Query, [string]$BodyJson, [string]$ApiVersion = '7.1-preview')
    $cli = @('devops', 'invoke', '--org', $Org, '--area', $Area, '--resource', $Resource, '--http-method', $Method, '--api-version', $ApiVersion, '-o', 'json', '--only-show-errors')
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
# The bootstrap's shape goes first: if it persists, Initialize-AzureDevOps.ps1 needs no other change.
$attempts += @{ name = 'IMS descriptor + identityId + displayName (bootstrap shape)'; body = @(@{ identityDescriptor = $id.descriptor; identityId = $id.id; displayName = $Identity; role = $Role }) }
if ($graph) {
    $attempts += @{ name = 'graph descriptor only';                       body = @(@{ identityDescriptor = $graph; role = $Role }) }
    $attempts += @{ name = 'graph descriptor + identityId + displayName'; body = @(@{ identityDescriptor = $graph; identityId = $id.id; displayName = $Identity; role = $Role }) }
}
$attempts += @{ name = 'IMS descriptor only';                                        body = @(@{ identityDescriptor = $id.descriptor; role = $Role }) }
$attempts += @{ name = 'identityId only';                                            body = @(@{ identityId = $id.id; displayName = $Identity; role = $Role }) }
$attempts += @{ name = 'object descriptor (7.1 reference shape)';                    body = @(@{ identityDescriptor = @{ identityType = $type; identifier = $identifier }; identityId = $id.id; displayName = $Identity; role = $Role }) }
# Shapes the first six attempts did not cover (2026-09-21): the FeedRole enum as its integer, the graph
# subjectDescriptor next to the IMS descriptor, and the org-level build service -- if that last one
# persists, project-scoped identities are what the route refuses, which changes the workaround.
$attempts += @{ name = 'role as the FeedRole integer (contributor = 3)';              body = @(@{ identityDescriptor = $id.descriptor; identityId = $id.id; role = 3 }) }
$attempts += @{ name = 'subjectDescriptor field alongside the IMS descriptor';         body = @(@{ subjectDescriptor = $id.subjectDescriptor; identityDescriptor = $id.descriptor; identityId = $id.id; displayName = $Identity; role = $Role }) }
$collFound = @((Invoke-Cli -Method GET -Area IMS -Resource Identities -Query @('searchFilter=General', "filterValue=Project Collection Build Service ($orgName)", 'queryMembership=None')).value)
$coll = $collFound | Where-Object { $_.descriptor -like 'Microsoft.TeamFoundation.ServiceIdentity;*:Build:*' } | Select-Object -First 1
if ($coll) { $attempts += @{ name = "org-level build service ($($coll.providerDisplayName))"; body = @(@{ identityDescriptor = $coll.descriptor; identityId = $coll.id; displayName = $coll.providerDisplayName; role = $Role }) } }
foreach ($a in $attempts) {
    $json = ConvertTo-Json -InputObject $a.body -Depth 6 -Compress
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
# 4. Nothing persisted. "The API returns 200 and does nothing" has two very different causes and
#    the fix differs, so work out which one this is instead of guessing.
"`n--- diagnostics: no shape persisted, finding out why ---"

$feedBase = "https://feeds.dev.azure.com/$orgName/$([uri]::EscapeDataString($Project))/_apis/packaging/Feeds"
function Get-Feed {
    if ($headers) { return Invoke-RestMethod -Method GET -Uri "${feedBase}/${Feed}?api-version=7.1-preview.1" -Headers $headers }
    return Invoke-Cli -Method GET -Area packaging -Resource feeds -Route @("project=$Project", "feedId=$Feed")
}

$feedObj = $null
try { $feedObj = Get-Feed } catch { "could not read the feed: $($_.Exception.Message)" }
# A single-feed GET can come back wrapped as {count, value}; unwrap before use.
if ($feedObj -and $feedObj.PSObject.Properties['value']) { $feedObj = @($feedObj.value)[0] }
if ($feedObj) { "feed: name=$($feedObj.name) id=$($feedObj.id)" }

# Probe A: can this credential write to the feeds service at all? Setting the description to the
# value it already has is a write that needs Packaging (read, write and manage) and changes nothing.
# A silent no-op on an under-scoped token looks exactly like the permissions failure above, so this
# is what separates "wrong scope" from "this endpoint is broken".
$canWrite = $null
if ($feedObj) {
    $probe = ConvertTo-Json -InputObject @{ description = $feedObj.description } -Compress
    try {
        if ($headers) { $null = Invoke-RestMethod -Method PATCH -Uri "${feedBase}/$($feedObj.id)?api-version=7.1-preview.1" -Headers $headers -ContentType 'application/json' -Body $probe }
        else { $null = Invoke-Cli -Method PATCH -Area packaging -Resource feeds -Route @("project=$Project", "feedId=$($feedObj.id)") -BodyJson $probe }
        $canWrite = $true
        "probe A (feed description write): accepted -- this credential CAN write to the feeds service"
    }
    catch {
        $canWrite = $false
        "probe A (feed description write): REJECTED -- $($_.Exception.Message)"
    }
}

# Probe B: address the feed by GUID rather than by name. Several packaging routes behave differently
# for the two, and every attempt above used the name.
if ($feedObj -and $feedObj.id -and $feedObj.id -ne $Feed) {
    $body = ConvertTo-Json -InputObject @(@{ identityDescriptor = ($graph ?? $id.descriptor); identityId = $id.id; displayName = $Identity; role = $Role }) -Depth 6 -Compress
    try {
        if ($headers) { $null = Invoke-RestMethod -Method PATCH -Uri "${feedBase}/$($feedObj.id)/permissions?api-version=7.1-preview.1" -Headers $headers -ContentType 'application/json' -Body $body }
        else { $null = Invoke-Cli -Method PATCH -Area packaging -Resource permissions -Route @("project=$Project", "feedId=$($feedObj.id)") -BodyJson $body }
        $after = Get-Permissions | Where-Object $isTarget | Select-Object -First 1
        if ($after -and $after.role -in @($Role, 'administrator')) { "ok: feed addressed by GUID worked -- '$Identity' is now $($after.role)"; exit 0 }
        "probe B (feed by GUID): still not persisted"
    }
    catch { "probe B (feed by GUID): request failed -- $($_.Exception.Message)" }
}

# Probe C: older api-versions of the same route.
foreach ($ver in @('6.0-preview.1', '7.0-preview.1')) {
    $body = ConvertTo-Json -InputObject @(@{ identityDescriptor = ($graph ?? $id.descriptor); identityId = $id.id; displayName = $Identity; role = $Role }) -Depth 6 -Compress
    try {
        if ($headers) { $null = Invoke-RestMethod -Method PATCH -Uri "${feedBase}/${Feed}/permissions?api-version=$ver" -Headers $headers -ContentType 'application/json' -Body $body }
        else { $null = Invoke-Cli -Method PATCH -Area packaging -Resource permissions -Route @("project=$Project", "feedId=$Feed") -BodyJson $body -ApiVersion $ver }
        $after = Get-Permissions | Where-Object $isTarget | Select-Object -First 1
        if ($after -and $after.role -in @($Role, 'administrator')) { "ok: api-version $ver worked -- '$Identity' is now $($after.role)"; exit 0 }
        "probe C (api-version $ver): still not persisted"
    }
    catch { "probe C (api-version $ver): request failed -- $($_.Exception.Message)" }
}

"`n--- verdict ---"
if ($canWrite -eq $false) {
    Write-Warning @"
The credential cannot write to the feeds service at all, so this is a TOKEN SCOPE problem, not an
API defect. Reissue the PAT with 'Packaging (read, write and manage)' and run this script again.
Until then: Artifacts > $Feed > gear > Permissions > Add users/groups > '$Identity' > Contributor.
"@
}
elseif ($canWrite -eq $true) {
    Write-Warning @"
The credential CAN write to the feeds service (a feed description write was accepted), yet every
permissions PATCH returns 200 with an empty result and persists nothing. That points at the
permissions route itself rather than at scope or identity form, and the portal is the only known
path. Grant it there: Artifacts > $Feed > gear > Permissions > Add users/groups > '$Identity' >
Contributor, and record this in docs/reference-feedback.md.
"@
}
else {
    Write-Warning "Could not read the feed, so scope could not be tested. Grant in the portal: Artifacts > $Feed > gear > Permissions > Add users/groups > '$Identity' > Contributor."
}
exit 1
