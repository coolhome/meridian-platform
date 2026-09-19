#Requires -Version 7.2
<#
.SYNOPSIS
    Applies governance/policies/branch-policy-profiles.json to every mirrored repo.
    Idempotent: existing policies of the same type/scope are updated, not duplicated.
#>
[CmdletBinding()]
param(
    [string[]]$Folders,
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$ctx = Connect-MeridianAdo -Manifest $m -Pat $Pat
$profiles = Get-MeridianGovernanceFile -Manifest $m -Key branchPolicyProfiles
$tmp = Join-Path ([IO.Path]::GetTempPath()) "meridian-policies-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Get-ExistingPolicies([string]$RepoId) {
    $all = @(Invoke-AzCli repos policy list --repository-id $RepoId)
    return $all
}

function Find-Policy($Existing, [string]$TypeName, [string]$Branch, [scriptblock]$Extra) {
    foreach ($p in $Existing) {
        if ($p.type.displayName -ne $TypeName) { continue }
        $scope = @($p.settings.scope)[0]
        $ref = if ($Branch) { if ($Branch.EndsWith('/*')) { "refs/heads/$($Branch.TrimEnd('*'))" } else { "refs/heads/$Branch" } } else { $null }
        if ($Branch -and $scope.refName -ne $ref) { continue }
        if (-not $Branch -and $scope.PSObject.Properties['refName'] -and $scope.refName) { continue }
        if ($Extra -and -not (& $Extra $p)) { continue }
        return $p
    }
    return $null
}

function Set-ConfigPolicy([string]$RepoId, [string]$TypeName, [hashtable]$Settings, $Existing, [string]$Branch) {
    $typeId = Get-AdoPolicyTypeId -DisplayName $TypeName -Fallbacks $profiles.policyTypeFallbacks
    $scope = @{ repositoryId = $RepoId }
    if ($Branch) {
        $scope.refName = if ($Branch.EndsWith('/*')) { "refs/heads/$($Branch.TrimEnd('*'))" } else { "refs/heads/$Branch" }
        $scope.matchKind = if ($Branch.EndsWith('/*')) { 'Prefix' } else { 'Exact' }
    }
    $Settings.scope = @($scope)
    $cfg = @{ isBlocking = $true; isEnabled = $true; type = @{ id = $typeId }; settings = $Settings }
    $file = Join-Path $tmp "$([guid]::NewGuid().ToString('n')).json"
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding utf8
    $found = Find-Policy $Existing $TypeName $Branch $null
    if ($found) { $null = Invoke-AzCli repos policy update --id $found.id --config $file; Write-MeridianInfo "updated $TypeName" }
    else { $null = Invoke-AzCli repos policy create --config $file; Write-MeridianOk "created $TypeName" }
}

foreach ($repo in Get-MeridianMirroredRepos -Manifest $m -Folders $Folders) {
    Write-MeridianStep "policies for $($repo.name) (profile $($repo.policyProfile))"
    $adoRepo = Get-AdoRepository -Name $repo.name
    if (-not $adoRepo) { Write-MeridianWarn "repo missing; sync first"; continue }
    $profile = $profiles.profiles.($repo.policyProfile)
    if (-not $profile) { throw "profile '$($repo.policyProfile)' not defined" }
    $repoId = $adoRepo.id
    $existing = Get-ExistingPolicies $repoId

    # --- repository-level policies ---
    $rs = $profiles.repositorySettings
    Set-ConfigPolicy $repoId 'File size restriction' @{ maximumGitBlobSizeInBytes = [int64]$rs.maximumFileSizeMB * 1MB; useUncompressedSize = $false } $existing $null
    Set-ConfigPolicy $repoId 'Path Length restriction' @{ maxPathLength = $rs.maximumPathLength } $existing $null
    if ($rs.reservedNames) { Set-ConfigPolicy $repoId 'Reserved names restriction' @{} $existing $null }
    if ($rs.enforceConsistentCase) { Set-ConfigPolicy $repoId 'Git repository settings' @{ enforceConsistentCase = $true } $existing $null }
    if ($rs.blockedFilePatterns) { Set-ConfigPolicy $repoId 'File name restriction' @{ filenamePatterns = @($rs.blockedFilePatterns) } $existing $null }
    if ($rs.commitAuthorEmailPatterns) { Set-ConfigPolicy $repoId 'Commit author email validation' @{ authorEmailPatterns = @($rs.commitAuthorEmailPatterns) } $existing $null }

    foreach ($branch in $profiles.branches) {
        Write-MeridianInfo "branch $branch"
        $bArgs = ConvertTo-AdoBranchArgs -Branch $branch

        # approver count
        $ac = $profile.approverCount
        $found = Find-Policy $existing 'Minimum number of reviewers' $branch $null
        $common = @('--blocking', 'true', '--enabled', 'true', '--minimum-approver-count', $ac.minimumApproverCount, '--creator-vote-counts', $ac.creatorVoteCounts.ToString().ToLower(), '--allow-downvotes', $ac.allowDownvotes.ToString().ToLower(), '--reset-on-source-push', $ac.resetOnSourcePush.ToString().ToLower())
        if ($found) { $null = Invoke-AzCli repos policy approver-count update --id $found.id @common } else { $null = Invoke-AzCli repos policy approver-count create --repository-id $repoId @bArgs @common }

        # work item linking
        if ($profile.workItemLinking) {
            $found = Find-Policy $existing 'Work item linking' $branch $null
            if ($found) { $null = Invoke-AzCli repos policy work-item-linking update --id $found.id --blocking true --enabled true } else { $null = Invoke-AzCli repos policy work-item-linking create --repository-id $repoId @bArgs --blocking true --enabled true }
        }

        # comment resolution
        if ($profile.commentResolution) {
            $found = Find-Policy $existing 'Comment requirements' $branch $null
            if ($found) { $null = Invoke-AzCli repos policy comment-required update --id $found.id --blocking true --enabled true } else { $null = Invoke-AzCli repos policy comment-required create --repository-id $repoId @bArgs --blocking true --enabled true }
        }

        # merge strategy
        $ms = $profile.mergeStrategy
        $found = Find-Policy $existing 'Require a merge strategy' $branch $null
        $msArgs = @('--blocking', 'true', '--enabled', 'true', '--allow-squash', $ms.allowSquash.ToString().ToLower(), '--allow-no-fast-forward', $ms.allowNoFastForward.ToString().ToLower(), '--allow-rebase', $ms.allowRebase.ToString().ToLower(), '--allow-rebase-merge', $ms.allowRebaseMerge.ToString().ToLower())
        if ($found) { $null = Invoke-AzCli repos policy merge-strategy update --id $found.id @msArgs } else { $null = Invoke-AzCli repos policy merge-strategy create --repository-id $repoId @bArgs @msArgs }

        # build validation
        foreach ($bv in $profile.buildValidation) {
            $pipeline = $repo.pipelines | Where-Object { $_.kind -eq $bv.pipelineKind } | Select-Object -First 1
            if (-not $pipeline) { Write-MeridianWarn "no pipeline of kind $($bv.pipelineKind); build validation skipped"; continue }
            $def = Get-AdoPipelineDefinition -Name $pipeline.name
            if (-not $def) { Write-MeridianWarn "pipeline $($pipeline.name) not created yet; run New-AdoPipelines.ps1 then rerun"; continue }
            $found = Find-Policy $existing 'Build' $branch { param($p) $p.settings.buildDefinitionId -eq $def.id }
            $bvArgs = @('--blocking', 'true', '--enabled', 'true', '--build-definition-id', $def.id, '--display-name', $bv.displayName, '--queue-on-source-update-only', $bv.queueOnSourceUpdateOnly.ToString().ToLower(), '--manual-queue-only', $bv.manualQueueOnly.ToString().ToLower(), '--valid-duration', $bv.validDurationMinutes)
            if ($bv.pathFilter) { $bvArgs += @('--path-filter', $bv.pathFilter) }
            if ($found) { $null = Invoke-AzCli repos policy build update --id $found.id @bvArgs } else { $null = Invoke-AzCli repos policy build create --repository-id $repoId @bArgs @bvArgs }
        }

        # required reviewers by path
        foreach ($rr in $profile.requiredReviewers) {
            $identity = Get-AdoIdentity -Name $rr.group
            if (-not $identity) { Write-MeridianWarn "group '$($rr.group)' not found; required reviewer skipped"; continue }
            $paths = ($rr.pathFilters -join ';')
            $found = Find-Policy $existing 'Required reviewers' $branch { param($p) ($p.settings.requiredReviewerIds -contains $identity.id) -and (($p.settings.filenamePatterns -join ';') -eq $paths) }
            $rrArgs = @('--blocking', 'true', '--enabled', 'true', '--required-reviewer-ids', $identity.id, '--message', $rr.message, '--path-filter', $paths)
            if ($found) { $null = Invoke-AzCli repos policy required-reviewer update --id $found.id @rrArgs } else { $null = Invoke-AzCli repos policy required-reviewer create --repository-id $repoId @bArgs @rrArgs }
            if ($rr.minimumApproverCount -gt 1) {
                # the CLI has no minimum count for required reviewers; set it through the REST config
                $cfgId = if ($found) { $found.id } else { (Find-Policy (Get-ExistingPolicies $repoId) 'Required reviewers' $branch { param($p) $p.settings.requiredReviewerIds -contains $identity.id }).id }
                $cfg = Invoke-AdoRest -ProjectScoped -Path "policy/configurations/$cfgId"
                $cfg.settings | Add-Member -NotePropertyName minimumApproverCount -NotePropertyValue $rr.minimumApproverCount -Force
                $null = Invoke-AdoRest -Method PUT -ProjectScoped -Path "policy/configurations/$cfgId" -Body $cfg
            }
        }
        Write-MeridianOk "branch $branch policies applied"
    }
}
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nBranch policies applied."
