#Requires -Version 7.2
<#
.SYNOPSIS
    One-time (idempotent) bootstrap of the Azure DevOps execution plane from the manifest
    and governance files.
.DESCRIPTION
    Project -> pipeline settings -> security groups -> teams + area paths -> iterations ->
    Artifacts feed -> service connections (workload identity federation) ->
    variable groups -> environments + checks. Safe to rerun.
.NOTES
    Check bodies follow the approvalsandchecks/check-configurations REST contract; the
    azp-reference explains the model but not the wire shape (see docs/reference-feedback.md).
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$Pat,
    [switch]$SkipServiceConnections,
    [switch]$SkipChecks
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$ctx = Connect-MeridianAdo -Manifest $m -Pat $Pat
$teams = Get-MeridianGovernanceFile -Manifest $m -Key teams
$iterations = Get-MeridianGovernanceFile -Manifest $m -Key iterations
$envDefs = Get-MeridianGovernanceFile -Manifest $m -Key environments
$pipelineSettings = Get-MeridianGovernanceFile -Manifest $m -Key projectPipelineSettings
$placeholder = '00000000-0000-0000-0000-000000000000'

# ---------------------------------------------------------------- project
Write-MeridianStep "project $($ctx.Project)"
$project = Get-AdoProject
if (-not $project) {
    $null = Invoke-AzCli devops project create --name $ctx.Project --process $m.azureDevOps.processTemplate --source-control git --visibility private --description $m.azureDevOps.projectDescription
    Start-Sleep -Seconds 5
    $project = Get-AdoProject
    Write-MeridianOk 'created project'
}
else { Write-MeridianInfo 'project exists' }

# ---------------------------------------------------------------- pipeline settings
Write-MeridianStep 'project pipeline settings (build/generalsettings)'
$body = @{}
foreach ($prop in $pipelineSettings.PSObject.Properties | Where-Object { $_.Name -notlike '$*' }) { $body[$prop.Name] = $prop.Value }
$applied = Invoke-AdoRest -Method PATCH -ProjectScoped -Path 'build/generalsettings' -Body $body
foreach ($k in $body.Keys) {
    if ($applied.PSObject.Properties[$k] -and $applied.$k -ne $body[$k]) { Write-MeridianWarn "$k stayed $($applied.$k): probably locked at organization level" }
}
Write-MeridianOk 'settings patched'

# ---------------------------------------------------------------- security groups
Write-MeridianStep 'security groups'
$groups = @((Invoke-AzCli devops security group list --project $ctx.Project).graphGroups)
foreach ($g in $teams.securityGroups) {
    $existing = $groups | Where-Object { $_.displayName -eq $g.name } | Select-Object -First 1
    if ($existing) { Write-MeridianInfo "$($g.name) exists" }
    else {
        $existing = Invoke-AzCli devops security group create --name $g.name --description $g.description --project $ctx.Project
        Write-MeridianOk "created group $($g.name)"
    }
    # members are principal names (e-mail); the sync identity that pushes mirrors lives here
    if ($g.PSObject.Properties['members'] -and $g.members) {
        $current = Get-AdoGroupMemberNames -Descriptor $existing.descriptor
        foreach ($member in $g.members) {
            if ($current -contains $member) { continue }
            $null = Invoke-AzCli devops security group membership add --group-id $existing.descriptor --member-id $member
            Write-MeridianOk "added $member to $($g.name)"
        }
    }
}

# ---------------------------------------------------------------- area paths + teams
Write-MeridianStep 'area paths and teams'
# `az boards area project show` takes an id, not a path, so walk the tree once and compare paths.
function Get-AreaPaths {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stack = [System.Collections.Stack]::new()
    $stack.Push((Invoke-AzCli boards area project list --depth 20))
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        if (-not $node) { continue }
        if ($node.PSObject.Properties['path'] -and $node.path) { $null = $set.Add($node.path) }
        if ($node.PSObject.Properties['children'] -and $node.children) { foreach ($c in $node.children) { $stack.Push($c) } }
    }
    return $set
}
$areaPaths = Get-AreaPaths
foreach ($ap in $teams.areaPaths) {
    $parts = $ap.Split('\')
    $name = $parts[-1]
    $parentPath = '\' + $ctx.Project + '\Area' + $(if ($parts.Count -gt 1) { '\' + ($parts[0..($parts.Count - 2)] -join '\') } else { '' })
    if ($areaPaths.Contains("$parentPath\$name")) { continue }
    $null = Invoke-AzCli boards area project create --name $name --path $parentPath
    $null = $areaPaths.Add("$parentPath\$name")
    Write-MeridianOk "area $ap"
}
$existingTeams = @(Invoke-AzCli devops team list --project $ctx.Project)
foreach ($t in $teams.teams) {
    if (-not ($existingTeams | Where-Object { $_.name -eq $t.name })) {
        $null = Invoke-AzCli devops team create --name $t.name --description $t.description --project $ctx.Project
        Write-MeridianOk "created team $($t.name)"
    }
    foreach ($ap in $t.areaPaths) {
        $full = "\$($ctx.Project)\Area\$ap"
        $isDefault = ($ap -eq $t.defaultAreaPath).ToString().ToLower()
        $null = Invoke-AzCli boards area team add --team $t.name --path $full --include-sub-areas $t.includeSubAreas.ToString().ToLower() --set-as-default $isDefault --project $ctx.Project -AllowFailure
    }
    Write-MeridianInfo "team $($t.name) -> $($t.areaPaths -join ', ')"
}

# ---------------------------------------------------------------- iterations
Write-MeridianStep 'iterations'
$start = [datetime]::Parse($iterations.start)
$rootIter = "\$($ctx.Project)\Iteration"
$existingIters = @((Invoke-AzCli boards iteration project list --depth 1).children | ForEach-Object { $_ })
for ($i = 1; $i -le $iterations.count; $i++) {
    $name = $iterations.namePattern.Replace('{n}', $i)
    $s = $start.AddDays(($i - 1) * $iterations.cadenceDays)
    $f = $s.AddDays($iterations.cadenceDays - 1)
    $iter = $existingIters | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $iter) {
        $iter = Invoke-AzCli boards iteration project create --name $name --path $rootIter --start-date $s.ToString('yyyy-MM-dd') --finish-date $f.ToString('yyyy-MM-dd')
        Write-MeridianOk "iteration $name ($($s.ToString('yyyy-MM-dd')) .. $($f.ToString('yyyy-MM-dd')))"
    }
    foreach ($teamName in $iterations.assignToTeams) {
        $null = Invoke-AzCli boards iteration team add --team $teamName --id $iter.identifier --project $ctx.Project -AllowFailure
    }
}

# ---------------------------------------------------------------- artifacts feed
Write-MeridianStep "artifacts feed $($m.azureDevOps.artifactsFeed)"
$feeds = @((Invoke-AdoRest -Service feeds -ProjectScoped -Path 'packaging/feeds' -ApiVersion '7.1-preview.1').value)
if ($feeds | Where-Object { $_.name -eq $m.azureDevOps.artifactsFeed }) { Write-MeridianInfo 'feed exists' }
else {
    $feedBody = @{
        name            = $m.azureDevOps.artifactsFeed
        description     = 'Meridian packages. Upstreams: nuget.org, npmjs. Meridian.* names are reserved to this feed via package source mapping in consumers.'
        upstreamEnabled = $true
        upstreamSources = @(
            @{ name = 'NuGet Gallery'; protocol = 'nuget'; location = 'https://api.nuget.org/v3/index.json'; upstreamSourceType = 'public' },
            @{ name = 'npmjs'; protocol = 'npm'; location = 'https://registry.npmjs.org/'; upstreamSourceType = 'public' }
        )
        capabilities    = 'defaultCapabilities'
    }
    $null = Invoke-AdoRest -Method POST -Service feeds -ProjectScoped -Path 'packaging/feeds' -Body $feedBody -ApiVersion '7.1-preview.1'
    Write-MeridianOk 'created feed with public upstreams'
}
# A feed created through REST grants nothing to the project build service, yet every pipeline restores through the
# feed (upstream packages are saved on first use) and platform-libraries publishes to it: Contributor covers both.
$buildServiceName = "$($ctx.Project) Build Service ($($ctx.OrgName))"
$buildService = @((Invoke-AdoRest -Service vssps -Path "identities?searchFilter=General&filterValue=$([uri]::EscapeDataString($buildServiceName))&queryMembership=None").value) |
    Where-Object { $_.descriptor -like "*:Build:$($project.id)" } | Select-Object -First 1
if (-not $buildService) { Write-MeridianWarn "identity '$buildServiceName' not found; grant Contributor on the feed by hand" }
else {
    $feedPath = "packaging/feeds/$($m.azureDevOps.artifactsFeed)/permissions"
    $perms = @((Invoke-AdoRest -Service feeds -ProjectScoped -Path $feedPath -ApiVersion '7.1-preview.1').value)
    # entries carry identityId only when the list is requested with includeIds (StrictMode: read the property defensively)
    $isBuildService = { $_.identityDescriptor -eq $buildService.descriptor -or ($_.PSObject.Properties['identityId'] -and $_.identityId -eq $buildService.id) }
    $current = $perms | Where-Object $isBuildService | Select-Object -First 1
    if ($current -and $current.role -in @('contributor', 'administrator')) { Write-MeridianInfo 'build service is a feed contributor' }
    else {
        # The service silently drops an entry it cannot resolve, so send the identity id as well and read back.
        $grant = ConvertTo-Json -InputObject @(@{ identityId = $buildService.id; identityDescriptor = $buildService.descriptor; role = 'contributor' }) -AsArray -Compress
        $null = Invoke-AdoRest -Method PATCH -Service feeds -ProjectScoped -Path $feedPath -Body $grant -ApiVersion '7.1-preview.1'
        $after = @((Invoke-AdoRest -Service feeds -ProjectScoped -Path "$feedPath?includeIds=true" -ApiVersion '7.1-preview.1').value) | Where-Object $isBuildService | Select-Object -First 1
        if ($after -and $after.role -in @('contributor', 'administrator')) { Write-MeridianOk "build service granted $($after.role) on the feed" }
        else { Write-MeridianWarn "feed permission for '$buildServiceName' (id $($buildService.id)) did not persist; grant Contributor in Artifacts > feed settings > Permissions" }
    }
}

# ---------------------------------------------------------------- service connections (WIF)
if (-not $SkipServiceConnections) {
    Write-MeridianStep 'service connections (workload identity federation)'
    foreach ($e in $envDefs.environments | Where-Object { $_.PSObject.Properties['azure'] }) {
        $name = $e.serviceConnection
        if (Get-AdoServiceEndpoint -Name $name) { Write-MeridianInfo "$name exists"; continue }
        if ($e.azure.subscriptionId -eq $placeholder -or $e.azure.identityClientId -eq $placeholder) {
            Write-MeridianWarn "$name skipped: fill governance/environments/environments.json azure.* for '$($e.name)'"
            continue
        }
        $cfg = @{
            data                             = @{ subscriptionId = $e.azure.subscriptionId; subscriptionName = $e.azure.subscriptionName; environment = 'AzureCloud'; scopeLevel = 'Subscription'; creationMode = 'Manual' }
            name                             = $name
            type                             = 'AzureRM'
            url                              = 'https://management.azure.com/'
            authorization                    = @{ parameters = @{ tenantid = $e.azure.tenantId; serviceprincipalid = $e.azure.identityClientId }; scheme = 'WorkloadIdentityFederation' }
            isShared                         = $false
            isReady                          = $true
            serviceEndpointProjectReferences = @(@{ projectReference = @{ id = $project.id; name = $ctx.Project }; name = $name; description = "Meridian $($e.name) (UAMI $($e.azure.identityName))" })
        }
        $file = Join-Path ([IO.Path]::GetTempPath()) "sc-$name.json"
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding utf8
        $resp = Invoke-AzCli devops service-endpoint create --service-endpoint-configuration $file
        Remove-Item $file -Force
        $issuer = $resp.authorization.parameters.workloadIdentityFederationIssuer
        $subject = $resp.authorization.parameters.workloadIdentityFederationSubject
        Write-MeridianOk "created $name (id $($resp.id))"
        Write-Host @"
    Create the federated credential on the identity with the issuer/subject Azure DevOps returned (do not hand-derive them):
      az identity federated-credential create -g $($e.azure.identityResourceGroup) --identity-name $($e.azure.identityName) --name fic-azdo-$($e.name) --issuer '$issuer' --subject '$subject' --audiences api://AzureADTokenExchange
"@ -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- variable groups
Write-MeridianStep 'variable groups'
function Set-VariableGroup([string]$Name, [hashtable]$Vars, [string]$Description) {
    $vg = Get-AdoVariableGroup -Name $Name
    $pairs = @($Vars.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
    if ($vg) {
        foreach ($kv in $Vars.GetEnumerator()) {
            if ($vg.variables.PSObject.Properties[$kv.Key]) { $null = Invoke-AzCli pipelines variable-group variable update --group-id $vg.id --name $kv.Key --value "$($kv.Value)" }
            else { $null = Invoke-AzCli pipelines variable-group variable create --group-id $vg.id --name $kv.Key --value "$($kv.Value)" }
        }
        Write-MeridianInfo "$Name updated"
    }
    else {
        $null = Invoke-AzCli pipelines variable-group create --name $Name --description $Description --authorize false --variables @pairs
        Write-MeridianOk "created $Name"
    }
}
$sharedEnv = $envDefs.environments | Where-Object { $_.name -eq 'shared' } | Select-Object -First 1
Set-VariableGroup 'meridian-shared' @{
    'Meridian.AcrName'              = $m.azureDevOps.containerRegistry
    'Meridian.Location'             = $sharedEnv.azure.location
    'Meridian.TenantId'             = $sharedEnv.azure.tenantId
    'Meridian.SharedSubscriptionId' = $sharedEnv.azure.subscriptionId
} 'Environment-agnostic values used by every pipeline stage. Not authorized for all pipelines; granted per pipeline by New-AdoPipelines.ps1.'
foreach ($e in $envDefs.environments | Where-Object { $_.PSObject.Properties['azure'] -and $_.name -ne 'shared' }) {
    $vars = @{
        AzureSubscriptionId = $e.azure.subscriptionId
        Location            = $e.azure.location
        UniqueSuffix        = $e.azure.uniqueSuffix
    }
    if ($e.PSObject.Properties['keyVaultName']) { $vars.KeyVaultName = $e.keyVaultName }
    Set-VariableGroup $e.variableGroup $vars "Non-secret values for environment $($e.name)."

    # optional Key Vault-linked group for secrets that must reach pipelines
    if ($e.PSObject.Properties['keyVaultName'] -and $e.keyVaultName -notlike '*CHANGE*') {
        $kvName = "$($e.variableGroup)-kv"
        if (-not (Get-AdoVariableGroup -Name $kvName)) {
            $sc = Get-AdoServiceEndpoint -Name $e.serviceConnection
            if ($sc) {
                # The service rejects an empty mapping, so seed it with the secret platform-infrastructure always writes.
                $kvBody = @{
                    name                           = $kvName
                    description                    = "Key Vault-linked secrets for $($e.name)"
                    type                           = 'AzureKeyVault'
                    providerData                   = @{ serviceEndpointId = $sc.id; vault = $e.keyVaultName; lastRefreshedOn = [DateTime]::UtcNow.ToString('o') }
                    variables                      = @{ 'appinsights-connection-string' = @{ enabled = $true; isSecret = $true; contentType = ''; value = $null } }
                    variableGroupProjectReferences = @(@{ projectReference = @{ id = $project.id; name = $ctx.Project }; name = $kvName })
                }
                $null = Invoke-AdoRest -Method POST -ProjectScoped -Path 'distributedtask/variablegroups' -Body $kvBody -ApiVersion '7.1-preview.2'
                Write-MeridianOk "created Key Vault-linked group $kvName (add further secrets in the Library UI or by PUT)"
            }
        }
    }
}

# ---------------------------------------------------------------- environments + checks
Write-MeridianStep 'environments and checks'
$tplRepo = Get-AdoRepository -Name $m.azureDevOps.templatesRepository
foreach ($e in $envDefs.environments) {
    $env = New-AdoEnvironmentIfMissing -Name $e.name -Description $e.description
    if ($SkipChecks) { continue }
    $resource = @{ type = 'environment'; id = "$($env.id)"; name = $e.name }
    $existingChecks = @((Invoke-AdoRest -ProjectScoped -Path "pipelines/checks/configurations?resourceType=environment&resourceId=$($env.id)&`$expand=settings" -ApiVersion '7.1-preview.1').value)

    foreach ($c in $e.checks) {
        $body = $null
        $label = $c.type
        switch ($c.type) {
            'approval' {
                $approvers = @()
                foreach ($g in $c.approvers) { $id = Get-AdoIdentity -Name $g; if ($id) { $approvers += @{ id = $id.id } } else { Write-MeridianWarn "approver '$g' not found" } }
                if ($approvers.Count -eq 0) { Write-MeridianWarn "approval on $($e.name) skipped: no approvers resolved"; continue }
                if ($existingChecks | Where-Object { $_.type.name -eq 'Approval' }) { Write-MeridianInfo "approval exists on $($e.name)"; continue }
                # A group is one approver entry; the service caps minRequiredApprovers at the entry count.
                $minRequired = [int]$c.minRequired
                if ($minRequired -gt $approvers.Count) {
                    Write-MeridianWarn "approval on $($e.name): minRequired $minRequired exceeds the $($approvers.Count) approver entr$(if ($approvers.Count -eq 1) { 'y' } else { 'ies' }); clamped. List individual users to require more than one approval."
                    $minRequired = $approvers.Count
                }
                $body = @{
                    type     = $envDefs.checkTypes.approval
                    settings = @{ approvers = $approvers; executionOrder = 'anyOrder'; minRequiredApprovers = $minRequired; instructions = $c.instructions; blockedApprovers = @(); requesterCannotBeApprover = [bool]$c.requesterCannotApprove }
                    resource = $resource
                    timeout  = [int]$c.timeoutMinutes
                }
            }
            'exclusiveLock' {
                if ($existingChecks | Where-Object { $_.type.name -eq 'ExclusiveLock' }) { Write-MeridianInfo "exclusive lock exists on $($e.name)"; continue }
                $body = @{ type = $envDefs.checkTypes.exclusiveLock; settings = @{}; resource = $resource; timeout = 43200 }
            }
            'requiredTemplate' {
                if (-not $tplRepo) { Write-MeridianWarn 'templates repo not mirrored yet; required template check deferred (rerun after Sync-ToAzureRepos.ps1)'; continue }
                $extends = foreach ($ref in $m.azureDevOps.allowedTemplateRefs) {
                    foreach ($t in $envDefs.requiredTemplates) {
                        @{ repositoryType = 'git'; repositoryName = "$($ctx.Project)/$($m.azureDevOps.templatesRepository)"; repositoryRef = $ref; templatePath = $t }
                    }
                }
                $existing = $existingChecks | Where-Object { $_.type.name -eq 'ExtendsCheck' } | Select-Object -First 1
                if ($existing) {
                    # The allowed refs change with every template tag; the service keeps the old list unless it is updated.
                    $want = @($extends | ForEach-Object { "$($_.repositoryName)|$($_.repositoryRef)|$($_.templatePath)" } | Sort-Object)
                    $have = @($existing.settings.extendsChecks | ForEach-Object { "$($_.repositoryName)|$($_.repositoryRef)|$($_.templatePath)" } | Sort-Object)
                    if (-not (Compare-Object $want $have)) { Write-MeridianInfo "required template exists on $($e.name)"; continue }
                    $update = @{ id = $existing.id; type = @{ id = $existing.type.id; name = $existing.type.name }; settings = @{ extendsChecks = @($extends) }; resource = $resource; timeout = $existing.timeout }
                    $null = Invoke-AdoRest -Method PATCH -ProjectScoped -Path "pipelines/checks/configurations/$($existing.id)" -Body $update -ApiVersion '7.1-preview.1'
                    Write-MeridianOk "required template on $($e.name) now lists $($m.azureDevOps.allowedTemplateRefs -join ', ')"
                    continue
                }
                $body = @{ type = $envDefs.checkTypes.extendsCheck; settings = @{ extendsChecks = @($extends) }; resource = $resource; timeout = 1440 }
            }
            'branchControl' {
                $label = 'branch control'
                $inputs = @{ allowedBranches = $c.allowedBranches; ensureProtectionOfBranch = ([bool]$c.ensureProtectionOfBranch).ToString().ToLower(); allowUnknownStatusBranch = 'false' }
                $existing = $existingChecks | Where-Object { $_.type.name -eq 'Task Check' -and $_.settings.definitionRef.name -ieq 'evaluatebranchProtection' } | Select-Object -First 1
                if ($existing) {
                    # Converge the inputs (allowed branches change when template tags or release patterns do).
                    $drift = @('allowedBranches', 'ensureProtectionOfBranch', 'allowUnknownStatusBranch') | Where-Object { "$($existing.settings.inputs.$_)" -ne "$($inputs[$_])" }
                    if (-not $drift) { Write-MeridianInfo "branch control exists on $($e.name)"; continue }
                    $update = @{
                        id       = $existing.id
                        type     = @{ id = $existing.type.id; name = $existing.type.name }
                        settings = @{ displayName = 'Branch control'; definitionRef = $existing.settings.definitionRef; inputs = $inputs; retryInterval = 0 }
                        resource = $resource
                        timeout  = $existing.timeout
                    }
                    $null = Invoke-AdoRest -Method PATCH -ProjectScoped -Path "pipelines/checks/configurations/$($existing.id)" -Body $update -ApiVersion '7.1-preview.1'
                    Write-MeridianOk "branch control on $($e.name) now allows $($c.allowedBranches)"
                    continue
                }
                $task = Get-AdoServerTask -Name 'evaluatebranchProtection'
                $definitionRef = if ($task) { @{ id = $task.id; name = $task.name; version = "$($task.version.major).$($task.version.minor).$($task.version.patch)" } }
                                 else { Write-MeridianWarn 'evaluatebranchProtection not listed by distributedtask/tasks; using documented id'; @{ id = '86b05a0c-73e6-4f7d-b3cf-e38f3b39a75b'; name = 'evaluatebranchProtection'; version = '0.0.1' } }
                $body = @{
                    type     = $envDefs.checkTypes.taskCheck
                    settings = @{
                        displayName   = 'Branch control'
                        definitionRef = $definitionRef
                        inputs        = $inputs
                        retryInterval = 0
                    }
                    resource = $resource
                    timeout  = 1440
                }
            }
            'businessHours' {
                $label = 'business hours'
                if ($existingChecks | Where-Object { $_.type.name -eq 'Task Check' -and $_.settings.displayName -eq 'Business hours' }) { Write-MeridianInfo "business hours exists on $($e.name)"; continue }
                # Documented shape (Learn, check-configurations add sample): task evaluateBusinessHours,
                # inputs businessDays/timeZone/startTime/endTime. Resolve the task at runtime, fall back to the documented id.
                $task = Get-AdoServerTask -Name 'evaluateBusinessHours'
                $definitionRef = if ($task) { @{ id = $task.id; name = $task.name; version = "$($task.version.major).$($task.version.minor).$($task.version.patch)" } }
                                 else { Write-MeridianWarn 'evaluateBusinessHours not listed by distributedtask/tasks; using documented id'; @{ id = '445fde2f-6c39-441c-807f-8a59ff2e075f'; name = 'evaluateBusinessHours'; version = '0.0.1' } }
                $body = @{
                    type     = $envDefs.checkTypes.taskCheck
                    settings = @{
                        displayName   = 'Business hours'
                        definitionRef = $definitionRef
                        inputs        = @{ businessDays = $c.daysOfWeek; timeZone = $c.timeZone; startTime = $c.startTime; endTime = $c.endTime }
                        retryInterval = 5
                    }
                    resource = $resource
                    timeout  = 1440
                }
            }
            default { Write-MeridianWarn "unknown check type $($c.type)"; continue }
        }
        if ($body) {
            $null = Invoke-AdoRest -Method POST -ProjectScoped -Path 'pipelines/checks/configurations' -Body $body -ApiVersion '7.1-preview.1'
            Write-MeridianOk "$label on $($e.name)"
        }
    }
}

Write-Host "`nBootstrap complete. Next: pwsh tooling/Publish-Platform.ps1" -ForegroundColor Green
