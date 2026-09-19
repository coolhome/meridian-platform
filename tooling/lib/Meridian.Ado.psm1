#Requires -Version 7.2
<#
.SYNOPSIS
    Shared helpers for Meridian Azure DevOps automation. Every script in tooling/ imports this.
.NOTES
    REST calls send X-TFS-FedAuthRedirect: Suppress so unauthenticated requests fail loudly
    instead of returning an HTML sign-in page with HTTP 200 (azp-reference, integrating page).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Ctx = $null
$script:PolicyTypes = $null
$script:ServerTasks = $null

function Write-MeridianStep { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-MeridianOk { param([string]$Message) Write-Host "    ok   $Message" -ForegroundColor Green }
function Write-MeridianInfo { param([string]$Message) Write-Host "    ..   $Message" -ForegroundColor DarkGray }
function Write-MeridianWarn { param([string]$Message) Write-Host "    warn $Message" -ForegroundColor Yellow }

function Get-MeridianRepoRoot {
    $root = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    }
    return (Resolve-Path $root).Path
}

function Get-MeridianManifest {
    [CmdletBinding()]
    param([string]$Path)
    $root = Get-MeridianRepoRoot
    if (-not $Path) { $Path = Join-Path $root 'repos.manifest.json' }
    $m = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 32
    if ($env:MERIDIAN_ADO_ORG_URL) { $m.azureDevOps.organizationUrl = $env:MERIDIAN_ADO_ORG_URL }
    if ($env:MERIDIAN_ADO_PROJECT) { $m.azureDevOps.project = $env:MERIDIAN_ADO_PROJECT }
    $m.azureDevOps.organizationUrl = $m.azureDevOps.organizationUrl.TrimEnd('/')
    $m | Add-Member -NotePropertyName RootPath -NotePropertyValue $root -Force
    $m | Add-Member -NotePropertyName ManifestPath -NotePropertyValue $Path -Force
    return $m
}

function Get-MeridianMirroredRepos {
    param([Parameter(Mandatory)]$Manifest, [string[]]$Folders)
    $repos = @($Manifest.repos | Where-Object { -not ($_.PSObject.Properties['mirror'] -and $_.mirror -eq $false) })
    if ($Folders -and $Folders.Count -gt 0) {
        $repos = @($repos | Where-Object { $Folders -contains $_.folder })
    }
    return $repos
}

function Get-MeridianGovernanceFile {
    param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$Key)
    $rel = $Manifest.governance.$Key
    if (-not $rel) { throw "Manifest governance.$Key is not set." }
    $path = Join-Path $Manifest.RootPath $rel
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 32
}

function Connect-MeridianAdo {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Manifest, [string]$Pat)
    if (-not $Pat) { $Pat = $env:AZDO_PAT }
    $env:PYTHONIOENCODING = 'utf-8'   # az devops otherwise drops non-cp1252 characters from JSON output on Windows
    $null = & az extension show --name azure-devops --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-MeridianInfo 'Installing azure-devops CLI extension'
        & az extension add --name azure-devops --only-show-errors | Out-Null
    }
    & az devops configure --defaults "organization=$($Manifest.azureDevOps.organizationUrl)" "project=$($Manifest.azureDevOps.project)" | Out-Null
    $orgName = ($Manifest.azureDevOps.organizationUrl -replace '^https://dev\.azure\.com/', '').Trim('/')
    if ($Pat) {
        $env:AZURE_DEVOPS_EXT_PAT = $Pat
        $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
        $script:Ctx = [pscustomobject]@{
            OrgUrl  = $Manifest.azureDevOps.organizationUrl
            OrgName = $orgName
            Project = $Manifest.azureDevOps.project
            Mode    = 'pat'
            Headers = @{
                Authorization           = "Basic $basic"
                'X-TFS-FedAuthRedirect' = 'Suppress'
                Accept                  = 'application/json'
            }
        }
        return $script:Ctx
    }
    # No PAT: rely on the credential the azure-devops extension already holds (az devops login).
    # REST calls are routed through `az devops invoke`; git needs Git Credential Manager (interactive).
    $probe = & az devops project list --organization $Manifest.azureDevOps.organizationUrl --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "No AZDO_PAT and the azure-devops extension cannot reach $($Manifest.azureDevOps.organizationUrl) (run 'az devops login' or set AZDO_PAT). Scopes for a PAT: Code (read, write, manage), Build (read, execute, manage), Project and Team (read, write), Environment (read, manage), Service Connections (read, query, manage), Variable Groups (read, create, manage), Graph (read, manage), Identity (read), Wiki (read, write), Packaging (read, write, manage), Work Items (read, write), Security (manage). Detail: $probe"
    }
    Write-MeridianInfo "no AZDO_PAT; using the azure-devops extension credential (REST via 'az devops invoke')"
    $script:Ctx = [pscustomobject]@{
        OrgUrl  = $Manifest.azureDevOps.organizationUrl
        OrgName = $orgName
        Project = $Manifest.azureDevOps.project
        Mode    = 'cli'
        Headers = $null
    }
    return $script:Ctx
}

# Path prefixes (after /_apis/) mapped to the location-service area/resource that `az devops invoke`
# needs when no PAT is available. Segments in braces become route parameters. Longest match wins.
$script:InvokeRoutes = @(
    @{ Pattern = 'build/generalsettings';                                     Area = 'build';               Resource = 'generalsettings' }
    @{ Pattern = 'build/definitions';                                         Area = 'build';               Resource = 'definitions' }
    @{ Pattern = 'build/definitions/{definitionId}';                          Area = 'build';               Resource = 'definitions' }
    @{ Pattern = 'packaging/feeds';                                           Area = 'packaging';           Resource = 'feeds' }
    @{ Pattern = 'packaging/feeds/{feedId}';                                  Area = 'packaging';           Resource = 'feeds' }
    @{ Pattern = 'pipelines/environments';                                    Area = 'distributedtask';     Resource = 'environments' }
    @{ Pattern = 'pipelines/environments/{environmentId}';                    Area = 'distributedtask';     Resource = 'environments' }
    @{ Pattern = 'pipelines/checks/configurations';                           Area = 'PipelinesChecks';     Resource = 'configurations' }
    @{ Pattern = 'pipelines/checks/configurations/{id}';                      Area = 'PipelinesChecks';     Resource = 'configurations' }
    @{ Pattern = 'pipelines/pipelinepermissions/{resourceType}/{resourceId}'; Area = 'pipelinePermissions'; Resource = 'pipelinePermissions' }
    @{ Pattern = 'pipelines/approvals';                                       Area = 'PipelinesApprovals';  Resource = 'approvals' }
    @{ Pattern = 'pipelines/approvals/{approvalId}';                          Area = 'PipelinesApprovals';  Resource = 'approvals' }
    @{ Pattern = 'distributedtask/variablegroups';                            Area = 'distributedtask';     Resource = 'variablegroups' }
    @{ Pattern = 'distributedtask/variablegroups/{groupId}';                  Area = 'distributedtask';     Resource = 'variablegroups' }
    @{ Pattern = 'distributedtask/tasks';                                     Area = 'distributedtask';     Resource = 'tasks' }
    @{ Pattern = 'distributedtask/resourceusage';                             Area = 'distributedtask';     Resource = 'resourceusage' }
    @{ Pattern = 'identities';                                                Area = 'IMS';                 Resource = 'Identities' }
    @{ Pattern = 'policy/configurations';                                     Area = 'policy';              Resource = 'configurations' }
    @{ Pattern = 'policy/configurations/{configurationId}';                   Area = 'policy';              Resource = 'configurations' }
    @{ Pattern = 'git/repositories/{repositoryId}/refs';                      Area = 'git';                 Resource = 'refs' }
    @{ Pattern = 'git/repositories/{repositoryId}/pushes';                    Area = 'git';                 Resource = 'pushes' }
)

function ConvertTo-AdoInvokeTarget {
    param([Parameter(Mandatory)][string]$Path)
    $qIdx = $Path.IndexOf('?')
    $query = if ($qIdx -ge 0) { $Path.Substring($qIdx + 1) } else { '' }
    $rel = if ($qIdx -ge 0) { $Path.Substring(0, $qIdx) } else { $Path }
    $segments = $rel.Trim('/').Split('/')
    foreach ($entry in ($script:InvokeRoutes | Sort-Object { $_.Pattern.Length } -Descending)) {
        $pattern = $entry.Pattern.Split('/')
        if ($pattern.Count -ne $segments.Count) { continue }
        $route = [ordered]@{}
        $ok = $true
        for ($i = 0; $i -lt $pattern.Count; $i++) {
            if ($pattern[$i] -match '^\{(\w+)\}$') { $route[$Matches[1]] = [uri]::UnescapeDataString($segments[$i]) }
            elseif ($pattern[$i] -ine $segments[$i]) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        $queryParams = [ordered]@{}
        foreach ($pair in ($query -split '&' | Where-Object { $_ })) {
            $k, $v = $pair.Split('=', 2)
            $queryParams[[uri]::UnescapeDataString($k)] = [uri]::UnescapeDataString(($v ?? ''))
        }
        return @{ Area = $entry.Area; Resource = $entry.Resource; Route = $route; Query = $queryParams }
    }
    throw "No 'az devops invoke' mapping for '$rel'. Add it to InvokeRoutes in Meridian.Ado.psm1 or set AZDO_PAT."
}

function Invoke-AdoCliRest {
    <# Same contract as Invoke-AdoRest, executed through `az devops invoke` with the extension's stored credential. #>
    param([string]$Method, [string]$Path, $Body, [string]$ApiVersion, [switch]$ProjectScoped)
    $ctx = Get-MeridianContext
    $t = ConvertTo-AdoInvokeTarget -Path $Path
    # the extension parses the version as a float plus an optional '-preview' flag; '7.1-preview.1' is rejected
    $version = $ApiVersion -replace '-preview(\.\d+)?$', '-preview'
    if ($ProjectScoped) { $t.Route['project'] = $ctx.Project }
    $azArgs = @('devops', 'invoke', '--organization', $ctx.OrgUrl, '--area', $t.Area, '--resource', $t.Resource, '--http-method', $Method, '--api-version', $version, '--output', 'json', '--only-show-errors')
    if ($t.Route.Count -gt 0) { $azArgs += '--route-parameters'; $azArgs += @($t.Route.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) }
    if ($t.Query.Count -gt 0) { $azArgs += '--query-parameters'; $azArgs += @($t.Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) }
    $file = $null
    try {
        if ($null -ne $Body) {
            $file = Join-Path ([IO.Path]::GetTempPath()) "ado-invoke-$([guid]::NewGuid().ToString('n')).json"
            $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 32 -Compress }
            [IO.File]::WriteAllText($file, $json, [Text.UTF8Encoding]::new($false))
            $azArgs += @('--in-file', $file, '--encoding', 'utf-8')
        }
        $out = & az @azArgs 2>&1
        $text = ($out | Where-Object { $_ -is [string] }) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            $err = ($out | Where-Object { $_ -isnot [string] } | ForEach-Object { $_.ToString() }) -join "`n"
            throw "ADO $Method $Path (az devops invoke --area $($t.Area) --resource $($t.Resource)) failed: $err $text"
        }
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        try { $obj = $text | ConvertFrom-Json -Depth 32 }
        catch {
            # some payloads (distributedtask/tasks) carry an empty property name, which only hashtables accept
            $obj = $text | ConvertFrom-Json -Depth 32 -AsHashtable
            if ($obj -is [hashtable]) { $obj.Remove('continuation_token') }
            return $obj
        }
        if ($obj -is [pscustomobject] -and $obj.PSObject.Properties['continuation_token']) { $obj.PSObject.Properties.Remove('continuation_token') }
        return $obj
    }
    finally { if ($file -and (Test-Path $file)) { Remove-Item $file -Force } }
}

function Get-MeridianContext {
    if (-not $script:Ctx) { throw 'Call Connect-MeridianAdo first.' }
    return $script:Ctx
}

function Invoke-AdoRest {
    <#
    .SYNOPSIS Calls an Azure DevOps REST endpoint with PAT auth.
    .PARAMETER Path  Path after /_apis/, e.g. 'pipelines/environments'
    .PARAMETER Service dev | vssps | vsrm | feeds | vsaex (host prefix)
    .PARAMETER ProjectScoped Prefix the path with the project.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [string]$ApiVersion = '7.1',
        [ValidateSet('dev', 'vssps', 'vsrm', 'feeds', 'vsaex')][string]$Service = 'dev',
        [switch]$ProjectScoped,
        [string]$ContentType = 'application/json'
    )
    $ctx = Get-MeridianContext
    if ($ctx.Mode -eq 'cli') {
        return Invoke-AdoCliRest -Method $Method -Path $Path -Body $Body -ApiVersion $ApiVersion -ProjectScoped:$ProjectScoped
    }
    $base = if ($Service -eq 'dev') { $ctx.OrgUrl } else { "https://$Service.dev.azure.com/$($ctx.OrgName)" }
    $scope = if ($ProjectScoped) { "/$([uri]::EscapeDataString($ctx.Project))" } else { '' }
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    $uri = "$base$scope/_apis/$Path$($sep)api-version=$ApiVersion"
    $params = @{ Method = $Method; Uri = $uri; Headers = $ctx.Headers; ContentType = $ContentType }
    if ($null -ne $Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 32 -Compress }
    }
    try {
        return Invoke-RestMethod @params
    }
    catch {
        $detail = $_.ErrorDetails.Message
        throw "ADO REST $Method $uri failed: $($_.Exception.Message) $detail"
    }
}

function Invoke-AzCli {
    <# Runs az with JSON output and throws on failure. Avoids --query quoting hazards on Windows. #>
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments, [switch]$AllowFailure)
    $out = & az @Arguments --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed: $out"
    }
    $text = ($out | Where-Object { $_ -is [string] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 32
}

function Get-AdoProject {
    $ctx = Get-MeridianContext
    return Invoke-AzCli devops project show --project $ctx.Project -AllowFailure
}

function Get-AdoRepository {
    param([Parameter(Mandatory)][string]$Name)
    return Invoke-AzCli repos show --repository $Name -AllowFailure
}

function New-AdoRepositoryIfMissing {
    param([Parameter(Mandatory)][string]$Name)
    $repo = Get-AdoRepository -Name $Name
    if ($repo) { Write-MeridianInfo "repo $Name exists"; return $repo }
    $repo = Invoke-AzCli repos create --name $Name
    Write-MeridianOk "created repo $Name"
    return $repo
}

function Get-AdoIdentity {
    <# Resolves a user or group to an identity (id, descriptor). Group names may be given as 'Group' or '[Project]\Group'. #>
    param([Parameter(Mandatory)][string]$Name)
    $ctx = Get-MeridianContext
    $candidates = @($Name)
    if ($Name -notmatch '^\[') { $candidates += "[$($ctx.Project)]\$Name" }
    foreach ($c in $candidates) {
        $res = Invoke-AdoRest -Service vssps -Path "identities?searchFilter=General&filterValue=$([uri]::EscapeDataString($c))&queryMembership=None"
        # identities omit customDisplayName unless one is set, so read properties defensively (StrictMode)
        $hit = @($res.value | Where-Object {
            $pdn = if ($_.PSObject.Properties['providerDisplayName']) { $_.providerDisplayName } else { $null }
            $cdn = if ($_.PSObject.Properties['customDisplayName']) { $_.customDisplayName } else { $null }
            $pdn -eq $c -or $cdn -eq $c -or $pdn -like "*\$Name"
        }) | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Get-AdoPipelineDefinition {
    param([Parameter(Mandatory)][string]$Name)
    $res = Invoke-AdoRest -ProjectScoped -Path "build/definitions?name=$([uri]::EscapeDataString($Name))"
    return @($res.value) | Select-Object -First 1
}

function Grant-AdoPipelinePermission {
    <# PATCH pipelines/pipelinepermissions/{resourceType}/{resourceId}. Resource ids: environment/variablegroup numeric, endpoint GUID, queue numeric, repository '{projectId}.{repoId}'. #>
    param(
        [Parameter(Mandatory)][ValidateSet('environment', 'endpoint', 'variablegroup', 'repository', 'queue', 'securefile')][string]$ResourceType,
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][int[]]$PipelineIds
    )
    $body = @{ pipelines = @($PipelineIds | ForEach-Object { @{ id = $_; authorized = $true } }) }
    $null = Invoke-AdoRest -Method PATCH -ProjectScoped -Path "pipelines/pipelinepermissions/$ResourceType/$ResourceId" -Body $body -ApiVersion '7.1-preview.1'
}

function Get-AdoPolicyTypeId {
    param([Parameter(Mandatory)][string]$DisplayName, $Fallbacks)
    if (-not $script:PolicyTypes) { $script:PolicyTypes = @(Invoke-AzCli repos policy type list) }
    $t = $script:PolicyTypes | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($t) { return $t.id }
    if ($Fallbacks -and $Fallbacks.PSObject.Properties[$DisplayName]) {
        Write-MeridianWarn "policy type '$DisplayName' not listed by the service; using documented fallback id"
        return $Fallbacks.$DisplayName
    }
    throw "Policy type '$DisplayName' not found."
}

function Get-AdoEnvironment {
    param([Parameter(Mandatory)][string]$Name)
    $res = Invoke-AdoRest -ProjectScoped -Path "pipelines/environments?name=$([uri]::EscapeDataString($Name))"
    return @($res.value | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

function New-AdoEnvironmentIfMissing {
    param([Parameter(Mandatory)][string]$Name, [string]$Description = '')
    $env = Get-AdoEnvironment -Name $Name
    if ($env) { Write-MeridianInfo "environment $Name exists (id $($env.id))"; return $env }
    $env = Invoke-AdoRest -Method POST -ProjectScoped -Path 'pipelines/environments' -Body @{ name = $Name; description = $Description }
    Write-MeridianOk "created environment $Name (id $($env.id))"
    return $env
}

function Get-AdoServiceEndpoint {
    param([Parameter(Mandatory)][string]$Name)
    $all = @(Invoke-AzCli devops service-endpoint list)
    return $all | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-AdoVariableGroup {
    param([Parameter(Mandatory)][string]$Name)
    $all = @(Invoke-AzCli pipelines variable-group list)
    return $all | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-AdoServerTask {
    <# Finds a server-side check task (e.g. evaluatebranchProtection, businessHours) by name; returns the newest version. #>
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:ServerTasks) { $script:ServerTasks = @((Invoke-AdoRest -Path 'distributedtask/tasks').value) }
    return $script:ServerTasks |
        Where-Object { $_.name -ieq $Name -or $_.friendlyName -ieq $Name } |
        Sort-Object { [int]$_.version.major }, { [int]$_.version.minor }, { [int]$_.version.patch } -Descending |
        Select-Object -First 1
}

function ConvertTo-AdoBranchArgs {
    <# 'release/*' -> prefix match on 'release/'; otherwise exact. #>
    param([Parameter(Mandatory)][string]$Branch)
    if ($Branch.EndsWith('/*')) { return @('--branch', $Branch.Substring(0, $Branch.Length - 1), '--branch-match-type', 'prefix') }
    return @('--branch', $Branch, '--branch-match-type', 'exact')
}

function Get-GitAuthHeader {
    <# Value for git -c http.extraheader=... so the PAT never appears in a remote URL. #>
    param([string]$Pat = $env:AZDO_PAT)
    if (-not $Pat) {
        Write-MeridianWarn 'no AZDO_PAT: git will authenticate through its credential helper (Git Credential Manager prompts in a browser the first time)'
        return $null
    }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    return "AUTHORIZATION: basic $basic"
}

function Get-GitConfigArgs {
    <# `-c http.extraheader=...` when a PAT header exists, nothing otherwise (credential helper). #>
    param([string]$AuthHeader)
    if ($AuthHeader) { return @('-c', "http.extraheader=$AuthHeader") }
    return @()
}

function Get-AdoRepoRemoteUrl {
    <# Same shape Azure Repos prints as remoteUrl (org name as user info) so Git Credential Manager keys one credential per organization. #>
    param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$RepoName)
    $org = $Manifest.azureDevOps.organizationUrl.TrimEnd('/')
    $orgName = ($org -replace '^https://dev\.azure\.com/', '').Trim('/')
    $project = [uri]::EscapeDataString($Manifest.azureDevOps.project)
    if ($org -match '^https://dev\.azure\.com/') { return "https://$orgName@dev.azure.com/$orgName/$project/_git/$RepoName" }
    return "$org/$project/_git/$RepoName"
}

Export-ModuleMember -Function *-*
