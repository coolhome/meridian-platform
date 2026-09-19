targetScope = 'subscription'

param environment string
param prefix string
param allowedLocations array

var assignedBy = 'Meridian platform-infrastructure pipeline'

var builtIn = {
  allowedLocations: 'e56962a6-4747-49cd-b67b-bf8b01975c4c' // gitleaks:allow (built-in policy definition id, public)
  requireTagOnResourceGroups: '96670d01-0a4d-4649-9c89-2d3abc0a5025' // gitleaks:allow (built-in policy definition id, public)
  storageDisablePublicNetworkAccess: 'b2982f36-99f2-4db5-8eff-283140c09693' // gitleaks:allow (built-in policy definition id, public)
}

resource locations 'Microsoft.Authorization/policyAssignments@2025-01-01' = {
  name: take('${prefix}-${environment}-locations', 24)
  properties: {
    displayName: 'Meridian ${environment}: allowed locations'
    description: 'Resources may only be created in the regions the platform operates in.'
    metadata: {
      assignedBy: assignedBy
    }
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.allowedLocations)
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

resource requireEnvTag 'Microsoft.Authorization/policyAssignments@2025-01-01' = {
  name: take('${prefix}-${environment}-rg-tag', 24)
  properties: {
    displayName: 'Meridian ${environment}: resource groups carry meridian:environment'
    description: 'Every resource group must carry the meridian:environment tag so cost and ownership roll up per environment.'
    metadata: {
      assignedBy: assignedBy
    }
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.requireTagOnResourceGroups)
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: 'meridian:environment'
      }
    }
  }
}

resource storagePublicAccess 'Microsoft.Authorization/policyAssignments@2025-01-01' = {
  name: take('${prefix}-${environment}-st-public', 24)
  properties: {
    displayName: 'Meridian ${environment}: audit storage public network access'
    description: 'Audit only: storage accounts reachable from public networks are reported, not blocked, until private endpoints arrive (ADR 0006 follow-up).'
    metadata: {
      assignedBy: assignedBy
    }
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.storageDisablePublicNetworkAccess)
    enforcementMode: 'DoNotEnforce'
    parameters: {
      effect: {
        value: 'Audit'
      }
    }
  }
}
