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
    if (-not $Pat) {
        throw 'Provide -Pat or set AZDO_PAT. Scopes: Code (read, write, manage), Build (read, execute, manage), Project and Team (read, write), Environment (read, manage), Service Connections (read, query, manage), Variable Groups (read, create, manage), Graph (read, manage), Identity (read), Wiki (read, write), Packaging (read, write, manage), Work Items (read, write), Security (manage).'
    }
    $env:AZURE_DEVOPS_EXT_PAT = $Pat
    $null = & az extension show --name azure-devops --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-MeridianInfo 'Installing azure-devops CLI extension'
        & az extension add --name azure-devops --only-show-errors | Out-Null
    }
    & az devops configure --defaults "organization=$($Manifest.azureDevOps.organizationUrl)" "project=$($Manifest.azureDevOps.project)" | Out-Null
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    $script:Ctx = [pscustomobject]@{
        OrgUrl  = $Manifest.azureDevOps.organizationUrl
        OrgName = ($Manifest.azureDevOps.organizationUrl -replace '^https://dev\.azure\.com/', '').Trim('/')
        Project = $Manifest.azureDevOps.project
        Headers = @{
            Authorization           = "Basic $basic"
            'X-TFS-FedAuthRedirect' = 'Suppress'
            Accept                  = 'application/json'
        }
    }
    return $script:Ctx
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
        $hit = @($res.value | Where-Object { $_.providerDisplayName -eq $c -or $_.customDisplayName -eq $c -or $_.providerDisplayName -like "*\$Name" }) | Select-Object -First 1
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
    if (-not $Pat) { throw 'AZDO_PAT is required for git operations against Azure Repos.' }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    return "AUTHORIZATION: basic $basic"
}

function Get-AdoRepoRemoteUrl {
    param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$RepoName)
    $org = $Manifest.azureDevOps.organizationUrl
    $project = [uri]::EscapeDataString($Manifest.azureDevOps.project)
    return "$org/$project/_git/$RepoName"
}

Export-ModuleMember -Function *-*
